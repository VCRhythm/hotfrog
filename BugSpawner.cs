using UnityEngine;

public class BugSpawner : Spawner {

	public int spawningForPlayerID = -1;

	[HideInInspector]public Vector4 buttonBarriers;
	
	public override void Reset (bool delayFade)
	{
        spawningForPlayerID = -1;

        base.Reset (delayFade);
	}
	
	public void MakeSpawnsLeave()
	{
		ControlBugSpawns((x) => x.Leave());
	}

	public void SpawnFlyBundle(int spawnAmount, Vector3 newPosition, int spawnPlayerID)
	{
		Reset(false);

        spawningForPlayerID = spawnPlayerID;
		maxSpawnCount = spawnAmount;
		spawningSpeedMin = 0;
		spawningSpeedMax = 0;

		_transform.position = newPosition;
		
		enabled = true;
	}

	public override void Activate() 
	{
		spawningSpeedMin = 2f;
		spawningSpeedMax = 2f;

		base.Activate();
	}

	#region Private Functions

	private void ControlBugSpawns(System.Action<Bug> action)
	{
		foreach(PooledObject obj in objectPool.ActiveObjects)
		{
			action(obj.gameObject.BugSpawnScript());
		}
	}
	
	protected override Transform CreateSpawn(int spawnIndex = -1)
	{
		Transform spawn = base.CreateSpawn(spawnIndex);

        if (spawningForPlayerID >= 0)
        {
            spawn.BugSpawnScript().MakeTame(spawningForPlayerID);
        }

		return spawn;
	}

	protected override void SetMovementToScreenSize()
	{
        base.SetMovementToScreenSize();

		adjustedMovements.Clear();
		for(int i = 0; i < Movements.Count; i++)
		{
			adjustedMovements.Add(new Vector3(Movements[i].x * halfScreenWidth * 1.2f, Movements[i].y * halfScreenHeight * 1.2f, Movements[i].z));
		}
	}

	#endregion Private Functions
}