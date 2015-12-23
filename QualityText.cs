using UnityEngine;

public class QualityText : PooledObject {

	public float lifetime = 0.5f;
	public bool canMove = false;

	private Vector2 speed { get { return SpawnManager.Instance.PullVector; } }

	void OnEnable () 
	{
		Invoke("Destroy", lifetime);
	}

	void FixedUpdate()
	{
		if(canMove)
		{
			transform.Translate(speed * (Time.deltaTime / 1.4f));
		}
	}

}