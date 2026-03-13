using UnityEngine;
using HotFrog.Spawning;

namespace HotFrog.Entities
{
	public class Splash : Spawn {

		[SerializeField] private float minXForce = -15f;
		[SerializeField] private float maxXForce = 15f;
		[SerializeField] private float yForce = 60f;
		[SerializeField] private float rotMod = 2f;

		Rigidbody2D _rigidbody;
		float force;
		float rotForce;

		protected override void Awake()
		{
			base.Awake();

			_rigidbody = GetComponent<Rigidbody2D>();
		}

		void OnEnable()
		{
			force = Random.Range(minXForce, maxXForce);
			rotForce = rotMod * Mathf.Sign(force);

			_rigidbody.rotation = 0;
			_rigidbody.AddForce(new Vector2(force, yForce), ForceMode2D.Impulse);
			_rigidbody.AddTorque(-rotForce, ForceMode2D.Impulse);

			Invoke("Destroy", 3f);
		}

	}
}
