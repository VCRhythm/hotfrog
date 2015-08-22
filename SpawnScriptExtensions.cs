using UnityEngine;
using System.Collections.Generic;

public static class SpawnScriptExtensions {
	public static Dictionary<Transform, Spawn> spawnLookupFromTransform = new Dictionary<Transform, Spawn>();
	public static Dictionary<GameObject, Spawn> spawnLookupFromGameObject = new Dictionary<GameObject, Spawn>();
	
	public static void Register(this Transform spawn)
	{
		Spawn spawnScript = spawn.GetComponent<Spawn>();
		
		spawnLookupFromTransform.Add(spawn, spawnScript);
		spawnLookupFromGameObject.Add(spawn.gameObject, spawnScript);
		spawnScript.deregisterAction = () => { spawn.Deregister(); };
	}
	
	public static void Deregister(this Transform spawn)
	{
		spawnLookupFromTransform.Remove (spawn);
		spawnLookupFromGameObject.Remove (spawn.gameObject);
	}

	public static Spawn SpawnScript(this Transform trans)
	{
		return spawnLookupFromTransform[trans];
	}
	
	public static Spawn SpawnScript(this GameObject go)
	{
		return spawnLookupFromGameObject[go];
	}

    public static Scenery ScenerySpawnScript(this GameObject go)
    {
        return spawnLookupFromGameObject[go] as Scenery;
    }

    public static Scenery ScenerySpawnScript(this Transform trans)
    {
        return spawnLookupFromTransform[trans] as Scenery;
    }

	public static Bug BugSpawnScript(this GameObject go)
	{
		return spawnLookupFromGameObject[go] as Bug;
	}

	public static Bug BugSpawnScript(this Transform trans)
	{
		return spawnLookupFromTransform[trans] as Bug;
	}

	public static Step StepSpawnScript(this GameObject go)
	{
		return spawnLookupFromGameObject[go] as Step;
	}
	
	public static Step StepSpawnScript(this Transform trans)
	{
		return spawnLookupFromTransform[trans] as Step;
	}

}