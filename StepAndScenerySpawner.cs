using UnityEngine;

public class StepAndScenerySpawner : ScenerySpawner {

    protected override Transform CreateSpawn(int spawnIndex = -1)
    {
        Transform spawn = base.CreateSpawn(spawnIndex);

        if (spawn != null)
        {
            LevelManager.Instance.TrackStep(spawn.GetComponentInChildren<Step>().transform);
        }

        return spawn;
    }
}
