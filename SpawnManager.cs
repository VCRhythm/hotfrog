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
    public Vector2 pullVector{ get; private set; }

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
        if (isInverted && (commandingStep != null && step != commandingStep))
        {
            return false;
        }

		commandingStep = step;

        Vector2 spawnDirection = isInverted ? -SpawnDirection : SpawnDirection;
        pullVector = spawnDirection * PullMultiplier(commandingStep.Position.y, spawnDirection.y * 40f) * stepPullMultiplier;

		if(!isInverted) ActivateSpawnersForDirection(spawnDirection != prevSpawnDirection);
        prevSpawnDirection = spawnDirection;

        return true;
	}

	public void ReleasePullingStep(Step step)
	{
        if (step == commandingStep)
        {
            DeactivateSpawners(activeStepSpawners);
			commandingStep = null;
			pullVector = Vector2.zero;
		}
	}

    public void HaltPulling()
    {
        ReleasePullingStep(commandingStep);
    }

    public void ResetLevelSpawners(Spawner.Type type, bool reverseType = false, bool delayFade = false)
	{
		foreach(Spawner spawner in levelSpawners)
		{
            if (spawner.spawnerType == type || (reverseType && spawner.spawnerType != type))
            {
                spawner.Reset(delayFade);
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
		for(int i=0; i< levelSpawners.Count; i++)
		{
            if (levelSpawners[i].spawnerType == type)
            {
                levelSpawners[i].Activate();
                Debug.Log(levelSpawners[i].name + "Activated");
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
                Debug.Log(spawner.name + ", " +spawnersInDirection[spawner.spawnDirection].Count);
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
        for (int i = 0; i < spawnerList.Count; i++)
        {
            spawnerList[i].Deactivate();
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