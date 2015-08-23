using UnityEngine;
using System.Collections.Generic;

public class SpawnManager : MonoBehaviour {

	// A singleton instance of this class
	private static SpawnManager instance;
	public static SpawnManager Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<SpawnManager>();
			return instance;
		}
	}

    public Vector2 SpawnDirection = -Vector2.up;
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
		CollectSpawners();
		EnableStepSpawners();
	}

	public void StartClimb()
	{
		ActivateSpawnersForDirection(false);

		TellSpawners(levelSpawners, (x) => x.StartClimb());
	}

	public void PullStep(Step step, bool isInverted, float stepPullMultiplier = 1f)
	{
		if(isInverted && (commandingStep != null && step != commandingStep)) return;

		commandingStep = step;

        Vector2 spawnDirection = isInverted ? -SpawnDirection : SpawnDirection;
        pullVector = spawnDirection * PullMultiplier(commandingStep.Position.y, spawnDirection.y * 40f) * stepPullMultiplier;

		if(!isInverted) ActivateSpawnersForDirection(true);
	}

	public void ReleasePullingStep(Step step)
	{
		if(step == commandingStep)
		{
			TellSpawners(activeStepSpawners, (x) => x.canSpawn = false);
			commandingStep = null;
			pullVector = Vector2.zero;
		}
	}

    public void HaltPulling()
    {
        ReleasePullingStep(commandingStep);
    }

    public void DisableSpawners(bool delayFade = false)
	{
		foreach(Spawner spawner in levelSpawners)
		{
			ToggleSpawner(spawner, false, delayFade);
		}
	}

	public void SpawnFlyBundle(int spawnAmount, Vector2 position, int playerID)
	{
        bugSpawner.SpawnFlyBundle(spawnAmount, position, playerID);
	}

	public void SpawnFromAll(Spawner.Type spawnerType, Vector2 direction, int spawnIndex)
	{
		for(int i = 0; i < levelSpawners.Count; i++)
		{
			if(levelSpawners[i].spawnerType == spawnerType && levelSpawners[i].spawnDirection == direction)
			{
				levelSpawners[i].CycleThroughMovementsAndSpawn(spawnIndex);
			}
		}
	}

	public void ActivateScenerySpawners()
	{
		for(int i=0; i< levelSpawners.Count; i++)
		{
            if (levelSpawners[i].spawnerType == Spawner.Type.Scenery)
            {
                levelSpawners[i].Activate(true);
                Debug.Log(levelSpawners[i].name + "Activated");
            }

		}
	}

    /*public void ActivateMenuSpawners()
    {
        for (int i = 0; i < spawners.Count; i++)
        {
            if (spawners[i].spawnerType == Spawner.Type.Menu)
            {
                spawners[i].Activate(true);
            }
        }
    }

    public void DeactivateMenuSpawners()
    {
        for (int i = 0; i < spawners.Count; i++)
        {
            if (spawners[i].spawnerType == Spawner.Type.Menu)
            {
                spawners[i].Reset(false);
            }
        }
    }*/

    #endregion Public Functions

    #region Private Functions

    private void EnableStepSpawners()
	{
		for(int i=0; i<levelSpawners.Count; i++)
		{
			if(levelSpawners[i].spawnerType == Spawner.Type.Step) 
			{
				ToggleSpawner(levelSpawners[i], true);
			}
		}
	}
	
	private void ToggleSpawner(Spawner spawner, bool isActive, bool delayFade = false)
	{
		if(!isActive && spawner.gameObject.activeInHierarchy)
		{
			spawner.Reset(delayFade);
		}

		spawner.enabled = isActive;
	}

	private void CollectSpawners()
	{
		levelSpawners.Clear ();
		foreach(List<Spawner> spawnerList in spawnersInDirection.Values)
		{
			spawnerList.Clear();
		}

		foreach(Spawner spawner in transform.FindChild("LevelSpawners").GetComponentsInChildren<Spawner>())
		{
			levelSpawners.Add(spawner);
			if(spawner.spawnerType == Spawner.Type.Step)
			{
				spawnersInDirection[(spawner as StepSpawner).spawnDirection].Add(spawner);
			}
		}
	}

	private void ActivateSpawnersForDirection(bool canMove)
	{
		TellSpawners(activeStepSpawners, (x) => x.canSpawn = false);
		activeStepSpawners = spawnersInDirection[SpawnDirection];
	    TellSpawners(activeStepSpawners, (x) => x.Activate(canMove));	
	}

	private void TellSpawners(List<Spawner> spawnerList, System.Action<Spawner> action)
	{
		for(int i = spawnerList.Count - 1; i >= 0; i--)
		{
			action(spawnerList[i]);
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

    #endregion Private Functions
}