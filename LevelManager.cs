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
            if (instance == null) instance = GameObject.FindObjectOfType<LevelManager>();
            return instance;
        }
    }

    public int levelCount = 0;
    public Level[] levels;

    public Step pullUpStepTransform;
    private PullStep pullUpStep;

    [HideInInspector]
    public bool canEndAnimation = false;
    public bool isInvincibleLevel { get { return !currentLevel.canDie; } }

    private Animator anim;
    private Lava lava;
    private Transform spawnerParent;
    private List<Transform> createdSpawners = new List<Transform>();
    private Overlay overlay1;
    private Overlay overlay2;
    private Transform wallParent;
    private Wall[] walls;
    private LensFlare flash;
    private Level currentLevel { get { return levels[levelCount]; } }
    private List<LevelEvent> timedLevelEvents = new List<LevelEvent>();
    private List<LevelEvent> stepLevelEvents = new List<LevelEvent>();
    private int timeEventIndex = 0;
    private int stepEventIndex = 0;
    private float startTime;
    private List<Transform> stepTransforms = new List<Transform>();
    private SpeckManager speckManager;

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

    void Awake()
    {
        anim = GetComponent<Animator>();

        LoadLevelAnimations();
    }

    void Start()
    {
        spawnerParent = GameObject.Find("Spawners").transform.FindChild("LevelSpawners").transform;
        flash = GameObject.Find("Flash").GetComponent<LensFlare>();
        wallParent = GameObject.Find("Walls").transform;
        walls = wallParent.GetComponentsInChildren<Wall>();

        overlay1 = new Overlay(GameObject.Find("Overlay").transform);
        overlay2 = new Overlay(GameObject.Find("Overlay2").transform);

        SetUpPullSteps();

        AudioManager.Instance.StartMusic(true, 1);

        SetUpLevel();
    }

    #region Public Functions

    public void ShowIntroAndStartLevel()
    {
        StartCoroutine(ShowIntro());
    }

    public void PullFrogY(float yMultiplier = 1f)
    {
        SpawnManager.Instance.SpawnDirection = -Vector2.up;
        SpawnManager.Instance.PullStep(pullUpStep.step, false, yMultiplier);
        pullUpStep.Reset();
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
        if(levelCount == 0 && stepCount < 2)
        {
            MoveGuidanceOnTouch(step);
        }
    }

    public void ResetInvincibleLevel()
    {
        PullFrogY(-3f);
        speckManager.MoveSpecks(stepTransforms[0]);
    }

    //Ends the level
    public void EndLevel(bool hasDied, bool canLoadNextLevel)
    {
        StopCoroutine("NextTimedEvent");
        Debug.Log("Disable spawners");
        SpawnManager.Instance.DisableSpawners(hasDied);
        VariableManager.Instance.SaveStats(HUD.Instance.BugsCaught, HUD.Instance.StepsClimbed);
        AudioManager.Instance.FadeOutMusic();

        if (hasDied)
        {
            lava.FrogFallSplash();
            lava.LiftHeat(false);
        }

        HideWalls();
        Debug.Log("Clean up spawners");
        CleanUpSpawners();

        if (canLoadNextLevel) levelCount++;
        Debug.Log("Set up level");
        SetUpLevel();
        if (canLoadNextLevel) StartLevel();
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

        StartLevel();
    }

    private void StartLevel()
    {
        timeEventIndex = 0;
        stepEventIndex = 0;

        //AudioManager.Instance.StartMusic(true, 0);
        lava.LowerHeat();

        if (currentLevel.overlayMaterial != null)
        {
            overlay1.Lift();
            overlay1.SetMaterial(currentLevel.overlayMaterial);
            overlay1.Fade(false);
        }

        if (currentLevel.backgroundMaterial != null)
        {
            SetWalls(currentLevel.backgroundMaterial);
        }

        startTime = Time.time;
        if (timedLevelEvents.Count > 0) StartCoroutine("NextTimedEvent");
    }

    private void FrogRelease()
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

    private void CleanUpSpawners()
    {
        for (int i = createdSpawners.Count - 1; i >= 0; i--)
        {
            DestroyImmediate(createdSpawners[i].gameObject);
        }
    }

    private void SetUpSpawners(Level level)
    {
        createdSpawners.Clear();

        for (int i = 0; i < level.spawners.Count; i++)
        {
            Transform spawner = Instantiate(level.spawners[i]) as Transform;
            Debug.Log(spawner + " created");
            spawner.SetParent(spawnerParent);
            createdSpawners.Add(spawner);
        }

        SpawnManager.Instance.SetUpLevel(level.initialSpawnDirection);
    }

    private void SetUpLevel()
    {
        stepTransforms.Clear();
        AudioManager.Instance.StartMusic(false, currentLevel.musicIndex);
        SetUpSpawners(currentLevel);
        FillLevelEvents();
        lava = FindObjectOfType<Lava>();
    }

    private void FillLevelEvents()
    {
        timedLevelEvents.Clear();
        stepLevelEvents.Clear();

        switch (levelCount)
        {
            case 0:
                speckManager = Instantiate(currentLevel.GetObject("SpeckManager")).GetComponent<SpeckManager>();
                timedLevelEvents.Add(new LevelEvent(true, 0, () => { SpawnManager.Instance.ActivateScenerySpawners(); TouchManager.Instance.StartLevel(); }));
                timedLevelEvents.Add(new LevelEvent(true, 1f, () => { speckManager.ActivateSpecks(Vector2.zero); }));
                timedLevelEvents.Add(new LevelEvent(true, 2f, () => { speckManager.MoveSpecks(stepTransforms[0]); }));

                stepLevelEvents.Add(new LevelEvent(false, 1, () => { TouchManager.Instance.frog.SlowlyLower(); }));
                stepLevelEvents.Add(new LevelEvent(false, 3, () =>
                {
                    StartCoroutine(Flash());
                    TouchManager.Instance.EndGame(false, true);
                    AudioManager.Instance.PlayIn(1f, AudioManager.Instance.splashSound);
                }));
                break;
            case 1:
                timedLevelEvents.Add(new LevelEvent(true, 2f, () => { StartClimb(); }));
                //stepLevelEvents.Add(new LevelEvent(false, 2f, () => { SpawnManager.Instance.SpawnFromAll(Spawner.Type.Scenery, Vector2.up, 0); SpawnManager.Instance.ActivateScenerySpawners(); }));
                /*stepLevelEvents.Add(new LevelEvent(false, 20f, () =>
              {
                  Flash();
                  EndLevel(false, true);
                  StartCoroutine(overlay1.Lower(1f));
                  AudioManager.Instance.PlayIn(1f, AudioManager.Instance.splashSound);
              }));*/
                break;
            case 2:
                stepLevelEvents.Add(new LevelEvent(false, 2f, () => { SpawnManager.Instance.ActivateScenerySpawners(); }));
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

    private void StartClimb()
    {
        lava.LiftHeat(true);

        TouchManager.Instance.frog.SlowlyLower();

        MenuManager.Instance.IsShowingReturnPanel = false;
        SpawnManager.Instance.StartClimb();
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
                case 0:
                    levels[i].levelAnimations.Add(() => { anim.SetTrigger("Nightfall"); });
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
}

#endregion