using UnityEngine;

public class StepAndScenerySpawner : ScenerySpawner {

    protected override Transform CreateSpawn(int spawnIndex = -1)
    {
        Transform spawn = base.CreateSpawn(spawnIndex);

        LevelManager.Instance.TrackStep(spawn.GetComponentInChildren<Step>()._transform);

        return spawn;
    }
}
