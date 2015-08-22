using UnityEngine;

public class KeepPositionFromParent : MonoBehaviour {

	private Transform _transform;
	private Transform parent;
	private Vector2 originalLocalPos;

	void Awake () 
	{
		_transform = transform;
		parent = _transform.parent;
		originalLocalPos = _transform.localPosition;
	}
	
	void Update () 
	{
		_transform.position = (Vector2)parent.position + originalLocalPos;
	}
}
