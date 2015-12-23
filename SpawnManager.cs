using UnityEngine;
using System.Collections.Generic;

public class SpawnManager : MonoBehaviour {

	// A singleton instance of this class
	private static SpawnManager instance;
	public static SpawnManager Instance {
		get {
			if (instance == null) instance = FindObjectOfType<SpawnManager>();
			return instance;
		}
	}

    public Vector2 SpawnDirection = -Vector2.up;
    private Vector2 prevSpawnDirection = -Vector2.up;
    private Vector2 pullVector;
    public Vector2 PullVector { get { return pullVector; } set { pullVector = value; if (isHalting && value != Vector2.zero) { isHalting = false; Debug.Log("stop halting"); } } }

    [HideInInspector] public bool isHalting = false;

    public Vector2[] spawnDirections = new Vector2[5]
	{
		new Vector2(0, -1f), new Vector2(0.5f, 0), new Vector2(-0.5f, 0), new Vector2(0.5f, -1f), new Vector2(-0.5f, -1f)
	};

    private BugSpawner bugSpawner;
    private List<Spawner> levelSpawners = new List<Spawner>();
    private List<Spawner> activeStepSpawners = new List<Spawner>();
    private Dictionary<Vector2, List<Spawner>> spawnersInDirection = new Dictionary<Vector2, List<Spawner>>();

    private Step commandingStep = null;

    #region Public Functions

    void Awake()
	{
		SetUpSpawnDirections();
	}

    void Start()
    {
        bugSpawner = transform.FindChild("Global").GetComponentInChildren<BugSpawner>();
    }

	public void SetUpLevel(Vector2 initialSpawnDirection)
	{
        SpawnDirection = initialSpawnDirection;
        prevSpawnDirection = initialSpawnDirection;

		CollectLevelSpawners();
	}

	public bool PullStep(Step step, bool isInverted = false, float stepPullMultiplier = 1f)
	{
        //Don't reset steps if not commanding step
        if (commandingStep != null && step != commandingStep)
        {
            return false;
        }

		commandingStep = step;

        Vector2 spawnDirection = isInverted ? -SpawnDirection : SpawnDirection;
        PullVector = spawnDirection * PullMultiplier(commandingStep.Position.y, spawnDirection.y * 40f) * stepPullMultiplier;
        Debug.Log(pullVector);

		if(!isInverted) ActivateSpawnersForDirection(spawnDirection != prevSpawnDirection);
        prevSpawnDirection = spawnDirection;

        return true;
	}

    public void Pull(Vector2 direction, float multiplier)
    {
        PullVector = direction * PullMultiplier(0, direction.y * 40f) * multiplier;
        Debug.Log(pullVector);

        ActivateSpawnersForDirection(direction != prevSpawnDirection);
        prevSpawnDirection = direction;
    }

	public void ReleasePullingStep(Step step)
	{
        if (step == commandingStep)
        {
            DeactivateSpawners(activeStepSpawners);
			commandingStep = null;
            Debug.Log(step + " release");
            PullVector = Vector2.zero;
		}
	}

    public void HaltPulling()
    {
        Debug.Log("halting");
        isHalting = true;
        ReleasePullingStep(commandingStep);
    }

    public void ResetLevelSpawners(Spawner.Type spawnerType, bool delayFade = false)
	{
		for(int i = levelSpawners.Count - 1; i >= 0; i--)
		{
            if (spawnerType == Spawner.Type.All || levelSpawners[i].spawnerType == spawnerType)
            {
                levelSpawners[i].Reset(delayFade);
            }
		}
	}

    public void SpawnFlyBundle(int spawnAmount, Vector2 position, int playerID)
	{
        bugSpawner.SpawnFlyBundle(spawnAmount, position, playerID);
	}

/*	public void SpawnFromAll(Spawner.Type spawnerType, Vector2 direction, int spawnIndex)
	{
		for(int i = 0; i < levelSpawners.Count; i++)
		{
			if(levelSpawners[i].spawnerType == spawnerType && levelSpawners[i].spawnDirection == direction)
			{
				levelSpawners[i].CycleThroughMovementsAndSpawn(spawnIndex);
			}
		}
	}*/

    public void ActivateLevelSpawners(Spawner.Type type)
    {
        Debug.Log("Activate Scenery " + type);
        for (int i=0; i< levelSpawners.Count; i++)
		{
            if (levelSpawners[i].spawnerType == type)
            {
                levelSpawners[i].Activate();
                //Debug.Log(levelSpawners[i].name + "Activated");
            }
		}
	}

    #endregion Public Functions

    #region Private Functions
	
	private void CollectLevelSpawners()
	{
        //Clear level spawner list
		levelSpawners.Clear ();

        //Clear spawners in direction arrays
        foreach (List<Spawner> spawnerList in spawnersInDirection.Values)
		{
			spawnerList.Clear();
		}

		foreach(Spawner spawner in transform.FindChild("LevelSpawners").GetComponentsInChildren<Spawner>())
		{
            //Add step spawners to direction arrays
			if(spawner.spawnerType == Spawner.Type.Step)
			{
				spawnersInDirection[spawner.spawnDirection].Add(spawner);
			}

            levelSpawners.Add(spawner);
        }
    }

	private void ActivateSpawnersForDirection(bool deactivatePrevDirection)
	{
        if (deactivatePrevDirection)
        {
            DeactivateSpawners(activeStepSpawners);
        }

		activeStepSpawners = spawnersInDirection[SpawnDirection];
        ActivateSpawners(activeStepSpawners);
	}

    private void ActivateSpawners(List<Spawner> spawnerList)
    {
        for(int i=0; i<spawnerList.Count; i++)
        {
            spawnerList[i].Activate();
        }
    }

    private void DeactivateSpawners(List<Spawner> spawnerList)
    {
        for (int i = spawnerList.Count - 1; i >= 0; i--)
        {
            if (spawnerList[i])
            {
                spawnerList[i].Deactivate(false);
            }
        }
    }

	private void SetUpSpawnDirections()
	{
		for(int i=0; i<spawnDirections.Length; i++)
		{
			spawnersInDirection.Add(spawnDirections[i], new List<Spawner>());
		}
	}

    private float PullMultiplier(float position, float target)
    {
        return 2f * Mathf.Abs(target - position);
    }

    /*	private void TellSpawners(List<Spawner> spawnerList, System.Action<Spawner> action)
	{
		for(int i = spawnerList.Count - 1; i >= 0; i--)
		{
			action(spawnerList[i]);
		}
	}
    */

    #endregion Private Functions
}