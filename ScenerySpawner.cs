using UnityEngine;

public class ScenerySpawner : Spawner {

    public bool spawnAllOnAwake;
    public float minSpawnScale = 1f;
    public float maxSpawnScale = 1f;
    public Color[] colorOptions;

	public override void Activate ()
	{
        if (spawnAllOnAwake)
        {
            isSpawning = true;
            CycleThroughMovementsAndSpawn();
        }

        base.Activate();
	}

	protected override void SetMovementToScreenSize()
	{
        base.SetMovementToScreenSize();

        adjustedMovements.Clear ();
		for(int i = 0; i < Movements.Count; i++)
		{
			adjustedMovements.Add(new Vector3(Movements[i].x * halfScreenWidth *(2/3f), Movements[i].y * halfScreenHeight, Movements[i].z));
		}
	}

    protected override Transform CreateSpawn(int spawnIndex = -1)
    {
        //Debug.Log(name + " spawn");
        Transform spawn = base.CreateSpawn(spawnIndex);

        if (spawn == null) return null;

        float spawnScale = Random.Range(minSpawnScale, maxSpawnScale);
        spawn.localScale = new Vector3(spawn.SpawnScript().originalScale.x * spawnScale, spawn.SpawnScript().originalScale.y * spawnScale, 1);

        if (colorOptions.Length > 0)
        {
            Color spawnColor = colorOptions[Random.Range(0, colorOptions.Length - 1)];
            for (int i = 0; i < spawn.SpawnScript().renderers.Length; i++)
            {
                if (spawn.ScenerySpawnScript().hasMaterial)
                    spawn.SpawnScript().renderers[i].material.SetColor("_Color", spawnColor);
                else
                    spawn.SpawnScript().renderers[i].color = spawnColor;
            }
        }
                
        return spawn;
    }
}