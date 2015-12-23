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

    [ReadOnly] public bool hasStarted = false;
    [ReadOnly] public int levelIndex = 0;
    [ReadOnly] public int nextLevelIndex = 0;
    public Level[] levels;

    public Transform aiPrefab;

    [HideInInspector] public bool canEndAnimation = false;

    private Animator sunAnimator;
    private Lava lava;
    private Transform spawnerParent;
    private List<Spawner> createdSpawners = new List<Spawner>();
    public List<LevelObject> levelObjects = new List<LevelObject>();
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
    private bool isPlaying = false;

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

        //Set up and Start level 0
        SetUpLevel();
        PlayLevel();
    }

    #region Public Functions

    //Ends the level, can be triggered by return button
    public void EndLevel(bool showMenu)
    {
        StopCoroutine("NextTimedEvent");
        isPlaying = false;
        hasStarted = false;
        
        if (levelIndex > 0)
        {
            Debug.Log("Disable spawners");
            SpawnManager.Instance.ResetLevelSpawners(Spawner.Type.All, showMenu);

            HideWalls();

            CleanUpSpawners();
            CleanUpObjects();
        }

        AudioManager.Instance.FadeOutMusic();

        if (!showMenu)
        {
            Debug.Log("Load level " + levelIndex + 1);
            // Load next level
            levelIndex++;
            SetUpLevel();
            StartLevel();
        }
        else
        {
            Debug.Log("Load menu");
            // Load Main Menu
            nextLevelIndex = levelIndex;
            levelIndex = 0;
            SetUpLevel();
        }

        StartCoroutine(CheckForPlayers());
    }

    //Used to identify initial steps
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

    public void ReportFall(Controller controller)
    {
        if (levelIndex > 1 && !ControllerManager.Instance.anyPlaying)
        {
            EndLevel(true);
        }
        else if(levelIndex == 1)
        {
            Debug.Log("Tutorial pull");
            SpawnManager.Instance.Pull(Vector2.up, 3f);
            ControllerManager.Instance.TellController(controller, (x) => { x.PlayLevel(); });
            speckManager.MoveSpecks(stepTransforms[0]);
        }
    }

    #endregion

    #region Private Functions

    IEnumerator CheckForPlayers()
    {
        bool hasStarted = false;
        while (!hasStarted)
        {
            if (!isPlaying && ControllerManager.Instance.allCanPlay)
            {
                Debug.Log("End Level " + levelIndex);
                EndLevel(false);
                isPlaying = true;
            }
            yield return new WaitForSeconds(1f);
        }
    }

    void TriggerAnimation()
    {
        canEndAnimation = true;
    }

    void StartLevel()
    {
        StartCoroutine(ShowIntroAndPlayLevel());
    }

    IEnumerator ShowIntroAndPlayLevel()
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

        PlayLevel();
    }

    void PlayLevel()
    {
        hasStarted = true;

        Debug.Log("Starting Level " + currentLevel.levelName);

        levelObjects.Clear();

        //Set up level spawners (might want to move this to setup)
        stepTransforms.Clear();
        SetUpSpawners(currentLevel);

        //Set up overlays
        if (currentLevel.overlayMaterial != null)
        {
            overlay1.SetMaterial(currentLevel.overlayMaterial);
            overlay1.Fade();
            overlay1.Lower();
        }

        if (currentLevel.overlay2Material != null)
        {
            overlay2.SetMaterial(currentLevel.overlay2Material);
            overlay2.Fade();
            overlay2.Lower();
        }

        //Set up background
        if (currentLevel.backgroundMaterial != null)
        {
            SetWalls(currentLevel.backgroundMaterial);
        }

        //Show Scenery
        SpawnManager.Instance.ActivateLevelSpawners(Spawner.Type.Scenery);

        //Start music
        AudioManager.Instance.StartMusic(true, currentLevel.musicIndex);

        //Lower Lava
        //lava.LowerHeat();

        //Play Level
        if (currentLevel.levelName != "Menu")
        {
            ControllerManager.Instance.TellControllers((x) => { x.PlayLevel(); });
        }
        else
        {
            ControllerManager.Instance.TellControllers((x) => { x.CanTouch = true; });
        }

        //Start level counters
        timeEventIndex = 0;
        stepEventIndex = 0;
        startTime = Time.time;
        if (currentLevel.hasTimedEvents)
        {
            StartCoroutine("NextTimedEvent");
        }
    }

    void SetWalls(Material material)
    {
        for (int i = 0; i < walls.Length; i++)
        {
            walls[i].SetMaterial(material);
        }

        wallParent.DOLocalMoveZ(0, 1f);
    }

    void HideWalls()
    {
        wallParent.DOKill();
        wallParent.DOLocalMoveZ(10f, 1f);
    }

    void CleanUpObjects()
    {
        Debug.Log("Clean up objects");
        for(int i = levelObjects.Count - 1; i>=0; i--)
        {
            Debug.Log("Clean up " + levelObjects[i].name);
            levelObjects[i].Destroy();
        }
    }

    void CleanUpSpawners()
    {
        Debug.Log("Clean up spawners");
        for (int i = createdSpawners.Count - 1; i >= 0; i--)
        {
            Debug.Log(i+ ": " + createdSpawners[i].name +" destroyed");
            createdSpawners[i].Deactivate(true);
        }

        createdSpawners.Clear();
    }

    private void SetUpSpawners(Level level)
    {
        Debug.Log("Set Up Spawners");
        Transform levelSpawnersTransform = new GameObject("Level " + level.levelName + " Spawners").transform;
        levelSpawnersTransform.SetParent(spawnerParent);

        for (int i = 0; i < level.spawners.Count; i++)
        {
            Spawner spawner = Instantiate(level.spawners[i]) as Spawner;
            Debug.Log(spawner + " created");
            
            spawner.transform.SetParent(levelSpawnersTransform);

            createdSpawners.Add(spawner);
        }

        SpawnManager.Instance.SetUpLevel(level.initialSpawnDirection);
    }

    private void SetUpLevel()
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
                AddTimedEvent(0f, () =>
                {
                    CreateObject("Clouds");
                });
                break;

            //Tutorial
            case 1:
                AddTimedEvent(0f, () =>
                {
                    CreateObject("Stars");
                    sunAnimator.SetBool("isNight", true);
                    speckManager = CreateObject("SpeckManager").GetComponent<SpeckManager>();
                });
                AddTimedEvent(0f, () => { SpawnManager.Instance.ActivateLevelSpawners(Spawner.Type.Step); });
                AddTimedEvent(2f, () => { speckManager.ActivateSpecks(stepTransforms[0]); });

                stepLevelEvents.Add(new LevelEvent(false, 3, () =>
                {
                    Debug.Log("Trigger Night");
                    speckManager.DeactivateSpecks();
                    sunAnimator.SetBool("isNight", false);
                    AddTimedEvent(Time.time + 2f, () => { SpawnManager.Instance.ResetLevelSpawners(Spawner.Type.Step); });
                    AddTimedEvent(Time.time + 3f, () => { overlay2.Lift(); sunAnimator.SetBool("isBlack", true); sunAnimator.SetBool("isNight", true); });
                    AddTimedEvent(Time.time + 3.5f, () => { AudioManager.Instance.PlayForAll(AudioManager.Instance.splashSound); lava.LiftHeat(true); });
                    AddTimedEvent(Time.time + 5f, () => { EndLevel(false); });
                }));
                break;
            
            //Pot
            case 2:
                //AddTimedEvent(2f, () => { SpawnManager.Instance.Pull(-Vector2.up, 1f); });
                //timedLevelEvents.Add(new LevelEvent(true, 5f, () => { Instantiate(aiPrefab); }));
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
                AddStepEvent(2, () => { SpawnManager.Instance.ActivateLevelSpawners(Spawner.Type.Scenery); });
                break;
        }
    }

    private LevelObject CreateObject(string objectName)
    {
        Debug.Log("Creating " + objectName);
        LevelObject go = Instantiate(currentLevel.GetObject(objectName));
        levelObjects.Add(go);

        return go;
    }

    private void AddTimedEvent(float time, System.Action action)
    {
        timedLevelEvents.Add(new LevelEvent(true, time, action));
    }

    private void AddStepEvent(int count, System.Action action)
    {
        stepLevelEvents.Add(new LevelEvent(false, count, action));
    }

    private IEnumerator Flash()
    {
        flash.enabled = true;
        yield return new WaitForSeconds(1f);
        flash.enabled = false;
    }

    private IEnumerator NextTimedEvent()
    {
        while (hasStarted)
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
            yield return new WaitForSeconds(1f);
        }
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
    
    #endregion
}
