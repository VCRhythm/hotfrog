using UnityEngine;
using HotFrog.Spawning;

namespace HotFrog.Entities
{
public class QualityText : PooledObject {

	[SerializeField] private float lifetime = 0.5f;
	[SerializeField] private bool canMove = false;

	private Vector2 speed => SpawnManager.Instance.PullVector;

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
}
