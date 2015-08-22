using UnityEngine;

public class QualityText : PooledObject {

	public float lifetime = 0.5f;
	public bool canMove = false;

	private Vector2 speed { get { return SpawnManager.Instance.pullVector; } }

	void OnEnable () 
	{
		Invoke("Destroy", lifetime);
	}

	void FixedUpdate()
	{
		if(canMove)
		{
			_transform.Translate(speed * (Time.deltaTime / 1.4f));
		}
	}

}