using UnityEngine;
using System.Collections.Generic;

[System.Serializable]
public class Level {
    public int musicIndex = 1;
    public Material backgroundMaterial;
    public Material overlayMaterial;
    public Material overlay2Material;
	public List<Transform> spawners = new List<Transform>();
	public Vector2 initialSpawnDirection = new Vector2(0, -1f);
	[HideInInspector] public List<LevelEvent> levelEvents = new List<LevelEvent>();
	public List<GameObject> levelObjects = new List<GameObject>();
    public List<System.Action> levelAnimations = new List<System.Action>();

	public GameObject GetObject(string name)
	{
		return levelObjects.Find(x=> x.name == name);
	}
}
