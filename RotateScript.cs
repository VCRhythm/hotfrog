using UnityEngine;
using System.Collections;

public class RotateScript : MonoBehaviour {

	private Transform _transform;
	public float rotateAngle = 0.01f;
	public Axis.Dir rotationAxis;
	private Axis axis;

	private bool isRotating = false;
	public bool IsRotating { get { return isRotating; } set { isRotating = value; if(value) StartRotation(); } }
	public bool startOnAwake = false;
	public bool isLocal = false;
	private Vector3 point = Vector3.zero;
	
	void Start()
	{
		if(startOnAwake) IsRotating = true;
	}

	private IEnumerator RotateTransform()
	{
		while(isRotating)
		{
			if(isLocal) point = _transform.position;
			_transform.RotateAround (point, axis.Vector, rotateAngle);
			yield return new WaitForFixedUpdate();
		}
	}

	private void StartRotation()
	{
		axis = new Axis(rotationAxis);
		_transform = transform;
		StartCoroutine(RotateTransform());
	}
}