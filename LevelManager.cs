using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using DG.Tweening;

public class LevelManager : MonoBehaviour
{

    // A singleton instance of this class
    private static LevelManager instance;
    public static LevelManager Instance
    {
        get
        {
            if (instance == null) instance = FindObjectOfType<LevelManager>();
            return instance;
        }
    }

    [ReadOnly] public bool isPlaying = false;
    public int levelIndex = 1;
    public Level[] levels;

    public Transform aiPrefab;
    public Step pullUpStepTransform;
    private PullStep pullUpStep;

    [HideInInspector] public bool canEndAnimation = false;

    private Animator sunAnimator;
    private Lava lava;
    private Transform spawnerParent;
    private List<Spawner> createdSpawners = new List<Spawner>();
    private List<GameObject> createdObjects = new List<GameObject>();
    private Overlay overlay1;
    private Overlay overlay2;
    private Transform wallParent;
    private Wall[] walls;
    private LensFlare flash;
    private Level currentLevel { get { return levels[levelIndex]; } }
    private List<LevelEvent> timedLevelEvents = new List<LevelEvent>();
    private List<LevelEvent> stepLevelEvents = new List<LevelEvent>();
    private int timeEventIndex = 0;
    private int stepEventIndex = 0;
    private float startTime;
    private List<Transform> stepTransforms = new List<Transform>();
    private SpeckManager speckManager;
    private List<IController> controllers = new List<IController>();

    private struct PullStep
    {
        public Step step;
        private Vector2 initialPos;

        public PullStep(Step step)
        {
            this.step = step;
            initialPos = step.Position;
        }

        public void Reset()
        {
            step.Position = initialPos;
        }
    }

    void Start()
    {
        //Stores level spawners in hierarchy
        spawnerParent = GameObject.Find("Spawners").transform.FindChild("LevelSpawners").transform;

        //Used to animate a flash
        flash = GameObject.Find("Flash").GetComponent<LensFlare>();

        wallParent = GameObject.Find("Walls").transform;
        walls = wallParent.GetComponentsInChildren<Wall>();
        lava = FindObjectOfType<Lava>();
        sunAnimator = FindObjectOfType<Sun>().GetComponent<Animator>();

        overlay1 = new Overlay(GameObject.Find("Overlay").transform);
        overlay2 = new Overlay(GameObject.Find("Overlay2").transform);

        SetUpPullSteps();

        //Set up and Start level 0
        SetUpLevel(0);
        StartLevel(levels[0]);

        //Set up current level
        SetUpLevel(levelIndex);
    }

    #region Public Functions

    public void ShowIntroAndStartLevel()
    {
        StartCoroutine(ShowIntro());
    }

    public void TrackStep(Transform stepTransform)
    {
        stepTransforms.Add(stepTransform);
    }

    //Triggers step count events during levels
    public void CheckForStepTrigger(Transform step, int stepCount)
    {
        while (stepLevelEvents.Count > stepEventIndex && stepLevelEvents[stepEventIndex].trigger <= stepCount)
        {
            stepLevelEvents[stepEventIndex++].action();
        }

        //Handle speck guidance
        if(levelIndex == 1)
        {
            MoveGuidanceOnTouch(step);
        }
    }

    public void ResetTutorial()
    {
        speckManager.MoveSpecks(stepTransforms[0]);
        AudioManager.Instance.PlayForAll(AudioManager.Instance.fallSound); 
    }

    public bool ReportFall(IController controller)
    {
        controllers.Remove(controller);

        if(controllers.Count == 0)
        {
            EndLevel(true, false);
            return true;
        }

        return false;
    }

    //Ends the level
    private void EndLevel(bool hasDied, bool canLoadNextLevel)
    {
        StopCoroutine("NextTimedEvent");
        isPlaying = false;

        Debug.Log("Disable spawners");
        SpawnManager.Instance.ResetLevelSpawners(Spawner.Type.Scenery, true, hasDied);
                
        if (hasDied)
        {
            lava.FallSplash();
            lava.LiftHeat(false);
        }

        HideWalls();

        Debug.Log("Clean up spawners");
        CleanUpSpawners(false);
        CleanUpObjects();

        if (canLoadNextLevel)
        {
            levelIndex++;
            SetUpLevel(levelIndex);
            ShowIntroAndStartLevel();
        }
        else
        {
            SetUpLevel(0);
            StartLevel(levels[0]);
        }        

        AudioManager.Instance.FadeOutMusic();
    }

    #endregion

    #region Private Functions

    private void TriggerAnimation()
    {
        canEndAnimation = true;
    }

    private IEnumerator ShowIntro()
    {
        for (int i = 0; i < currentLevel.levelAnimations.Count; i++)
        {
            currentLevel.levelAnimations[i]();

            while (!canEndAnimation)
            {
                yield return new WaitForSeconds(1f);
            }

            canEndAnimation = false;
        }

        StartLevel(currentLevel);
    }

    private void StartLevel(Level level)
    {
        Debug.Log("Starting Level " + level.levelName);

        //Clear leftover scenery
        if (level.clearAllScenery)
        {
            SpawnManager.Instance.ResetLevelSpawners(Spawner.Type.Scenery);
        }

        createdObjects.Clear();

        //Set up level spawners (might want to move this to setup)
        stepTransforms.Clear();
        SetUpSpawners(level);

        //Show Scenery
        SpawnManager.Instance.ActivateLevelSpawners(Spawner.Type.Scenery);

        //Start music
        AudioManager.Instance.StartMusic(true, currentLevel.musicIndex);

        //Lower Lava
        lava.LowerHeat();

        //Set up overlay
        if (currentLevel.overlayMaterial != null)
        {
            overlay1.Lift();
            overlay1.SetMaterial(currentLevel.overlayMaterial);
            overlay1.Fade(false);
        }

        //Set up background
        if (currentLevel.backgroundMaterial != null)
        {
            SetWalls(currentLevel.backgroundMaterial);
        }

        //Start level counters
        timeEventIndex = 0;
        stepEventIndex = 0;
        startTime = Time.time;
        if (timedLevelEvents.Count > 0) StartCoroutine("NextTimedEvent");

        //Play Level
        if (level.levelName != "Menu")
        {
            ControllerManager.Instance.TellControllers((x) => { x.PlayLevel(); });
        }
    }

    private void ReleaseY()
    {
        SpawnManager.Instance.ReleasePullingStep(pullUpStep.step);
    }

    private void SetWalls(Material material)
    {
        for (int i = 0; i < walls.Length; i++)
        {
            walls[i].SetMaterial(material);
        }

        wallParent.DOLocalMoveZ(0, 1f);
    }

    private void HideWalls()
    {
        wallParent.DOKill();
        wallParent.DOLocalMoveZ(10f, 1f);
    }

    private void CleanUpObjects()
    {
        for(int i=createdObjects.Count - 1; i>=0; i--)
        {
            Destroy(createdObjects[i]);
        }
    }

    private void CleanUpSpawners(bool cleanUpScenerySpawners)
    {
        for (int i = createdSpawners.Count - 1; i >= 0; i--)
        {
            if (createdSpawners[i].spawnerType != Spawner.Type.Scenery || cleanUpScenerySpawners)
            {
                Debug.Log(createdSpawners[i].name +" destroyed");
                DestroyImmediate(createdSpawners[i].gameObject);
            }
        }
    }

    private void SetUpSpawners(Level level)
    {
        createdSpawners.Clear();

        for (int i = 0; i < level.spawners.Count; i++)
        {
            Spawner spawner = Instantiate(level.spawners[i]) as Spawner;
            Debug.Log(spawner + " created");
            spawner.transform.SetParent(spawnerParent);
            createdSpawners.Add(spawner);
        }

        SpawnManager.Instance.SetUpLevel(level.initialSpawnDirection);
    }

    private void SetUpLevel(int levelIndex)
    {
        FillLevelEvents(levelIndex);
    }

    private void FillLevelEvents(int level)
    {
        timedLevelEvents.Clear();
        stepLevelEvents.Clear();

        switch (level)
        {
            //Menu
            case 0:
                break;

            //Tutorial
            case 1:
                timedLevelEvents.Add(new LevelEvent(true, 0f, () => 
                {
                    createdObjects.Add(Instantiate(currentLevel.GetObject("Stars")));
                    sunAnimator.SetBool("isNight", true);
                }));
                timedLevelEvents.Add(new LevelEvent(true, 0f, () => { SpawnManager.Instance.ActivateLevelSpawners(Spawner.Type.Step); }));
                speckManager = Instantiate(currentLevel.GetObject("SpeckManager")).GetComponent<SpeckManager>();
                createdObjects.Add(speckManager.gameObject);
                timedLevelEvents.Add(new LevelEvent(true, 1f, () => { speckManager.ActivateSpecks(Vector2.zero); }));
                timedLevelEvents.Add(new LevelEvent(true, 2f, () => { speckManager.MoveSpecks(stepTransforms[0]); }));

                stepLevelEvents.Add(new LevelEvent(false, 3, () =>
                {
                    StartCoroutine(Flash());
                    AudioManager.Instance.PlayIn(1f, AudioManager.Instance.splashSound);
                    EndLevel(false, true);
                }));
                break;
            
            //Pot
            case 2:
                timedLevelEvents.Add(new LevelEvent(true, 1f, () => { lava.LiftHeat(true); }));
                timedLevelEvents.Add(new LevelEvent(true, 2f, () => { PullY(3f); }));
                timedLevelEvents.Add(new LevelEvent(true, 5f, () => { Instantiate(aiPrefab); }));
                //stepLevelEvents.Add(new LevelEvent(false, 2f, () => { SpawnManager.Instance.SpawnFromAll(Spawner.Type.Scenery, Vector2.up, 0); SpawnManager.Instance.ActivateScenerySpawners(); }));
                /*stepLevelEvents.Add(new LevelEvent(false, 20f, () =>
              {
                  Flash();
                  EndLevel(false, true);
                  StartCoroutine(overlay1.Lower(1f));
                  AudioManager.Instance.PlayIn(1f, AudioManager.Instance.splashSound);
              }));*/
                break;
            
            //Kitchen
            case 3:
                stepLevelEvents.Add(new LevelEvent(false, 2f, () => { SpawnManager.Instance.ActivateLevelSpawners(Spawner.Type.Scenery); }));
                break;
        }
    }

    private IEnumerator Flash()
    {
        flash.enabled = true;
        yield return new WaitForSeconds(1f);
        flash.enabled = false;
    }

    private void LoadKitchenBackground()
    {
        StartCoroutine(Flash());
        SetWalls(levels[1].backgroundMaterial);
    }

    private void FadePot()
    {
        SetWalls(levels[0].backgroundMaterial);
        overlay2.Fade();
    }

    private IEnumerator NextTimedEvent()
    {
        while (timeEventIndex < timedLevelEvents.Count)
        {
            float nextEventTime = timedLevelEvents[timeEventIndex].trigger - (Time.time - startTime);
            if (nextEventTime > 0)
            {
                yield return new WaitForSeconds(nextEventTime);
            }
            timedLevelEvents[timeEventIndex++].action();
        }
    }

    private void SetUpPullSteps()
    {
        pullUpStep = new PullStep(pullUpStepTransform);
    }

    private void LoadLevelAnimations()
    {
        for (int i = 0; i < levels.Length; i++)
        {
            switch (i)
            {
                case 1:
                    break;
            }
        }
    }

    private void MoveGuidanceOnTouch(Transform touchedStep)
    {
        if (touchedStep == stepTransforms[1]) // Touched second step, so move specks to third step
        {
            speckManager.MoveSpecks(stepTransforms[2]);
        }
        else if (touchedStep == stepTransforms[0]) // Touched first step, so move specks to second step
        {
            speckManager.MoveSpecks(stepTransforms[1]);
        }
        else if (touchedStep == stepTransforms[2]) // Touched third step, so move specks away
        {
            speckManager.MoveSpecks(Vector2.right * 100f);
        }
    }

    private void PullY(float yMultiplier = 1f)
    {
        SpawnManager.Instance.SpawnDirection = -Vector2.up;
        SpawnManager.Instance.PullStep(pullUpStep.step, false, yMultiplier);
        pullUpStep.Reset();
    }
    
    #endregion
}
