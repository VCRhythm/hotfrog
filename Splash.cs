using UnityEngine;

public class Splash : Spawn {

	public float minXForce = -15f;
	public float maxXForce = 15f;
	public float yForce = 60f;
	public float rotMod = 2f;

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

		Invoke ("Destroy", 3f);
	}

}