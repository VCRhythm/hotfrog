using UnityEngine;
using System.Collections;

public class Preload : MonoBehaviour {

	// A singleton instance of this class
	private static Preload instance;
	public static Preload Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<Preload>();
			return instance;
		}
	}

	public Sprite[] spritesToLoad;

	IEnumerator Start () 
	{
		SpriteRenderer spriteRenderer = GetComponent<SpriteRenderer>();
		for(int i=0; i<spritesToLoad.Length; i++)
		{
			spriteRenderer.sprite = spritesToLoad[i];
			yield return null;
		}
		Destroy (gameObject);
	}
}
