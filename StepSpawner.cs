using UnityEngine;

public class StepSpawner : Spawner
{
    private Transform newSpawn;
    private Step newStep;

    void OnEnable()
    {
        canSpawn = false;
    }

    #region Public Functions

    public override void Reset(bool delayFade)
    {
        base.Reset(delayFade);

        SpawnManager.Instance.SpawnDirection = -Vector2.up;
        _transform.position = new Vector2(0, 20f);
    }

    public override void Activate(bool canMove)
    {
        if (canMove)
            Move();

        canSpawn = true;
    }

    public override void StartClimb()
    {
        StartCoroutine(StartSpawning(false));
    }

    #endregion Public Functions

    #region Private Functions

    protected override Transform CreateSpawn(int spawnIndex = -1)
    {
        newSpawn = base.CreateSpawn(spawnIndex);
        if (newSpawn == null) return null;

        newStep = newSpawn.StepSpawnScript();

        if (!newStep.canBeSpawned(spawnCount))
        {
            newStep.Destroy();
            spawnCount--;
            CreateSpawn();
            return null;
        }

        LevelManager.Instance.TrackStep(newSpawn);

        return newSpawn;
    }

    protected override void SetMovementToScreenSize()
    {
        base.SetMovementToScreenSize();

        adjustedMovements.Clear();
        for (int i = 0; i < Movements.Count; i++)
        {
            adjustedMovements.Add(new Vector3(Movements[i].x * halfScreenWidth, Movements[i].y * halfScreenHeight, Movements[i].z));
        }
    }

    #endregion Private Functions
}