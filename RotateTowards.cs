using UnityEngine;

public class RotateTowards : MonoBehaviour {

	Transform _transform;
	Rigidbody2D parentRB;
	public float rotateSpeed = 100f;
	float velocity;
	public Vector3 direction;
	public bool checkParent = false;

	void Awake()
	{
		_transform = transform;
	}
	
	void Update () 
	{
		_transform.rotation = Quaternion.Lerp(_transform.rotation, Quaternion.Euler(direction), Time.time * rotateSpeed);
	}
}
