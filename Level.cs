using UnityEngine;
using System.Collections.Generic;

[System.Serializable]
public class Level {
    public string levelName = "";
    public int musicIndex = 1;
    public bool hasTimedEvents = true;
    public bool clearAllScenery = true;
    public Material backgroundMaterial;
    public Material overlayMaterial;
    public Material overlay2Material;
	public List<Spawner> spawners = new List<Spawner>();
	public Vector2 initialSpawnDirection = new Vector2(0, -1f);
	[HideInInspector] public List<LevelEvent> levelEvents = new List<LevelEvent>();
	public List<LevelObject> levelObjects = new List<LevelObject>();
    public List<System.Action> levelAnimations = new List<System.Action>();

	public LevelObject GetObject(string name)
	{
		return levelObjects.Find(x => x.name == name);
	}
}
