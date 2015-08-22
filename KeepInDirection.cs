using UnityEngine;

public class KeepInDirection : MonoBehaviour {

	private Transform _transform;
	public Vector2 direction = Vector2.up;

	void Awake () 
	{
		_transform = transform;	
	}
	
	void Update () 
	{
		_transform.up = direction;	
	}
}
