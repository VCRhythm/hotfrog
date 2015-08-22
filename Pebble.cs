using UnityEngine;

public class Pebble : Spawn {

	#region Fields

	public float minSpeed;
	public float maxSpeed;

	private Vector2 speedVector;
	private Rigidbody2D _rigidbody;

	#endregion Fields

	#region Component Segments

	protected override void Awake ()
	{
		base.Awake ();
		_rigidbody = GetComponent<Rigidbody2D>();
	}

	void OnEnable()
	{
		speedVector = new Vector2(0, -Random.Range(minSpeed, maxSpeed));
	}

	void FixedUpdate () 
	{
		_rigidbody.AddForce(speedVector, ForceMode2D.Force);
	}
	
	#endregion Component Segments

	#region Functions

	public void ChangeSpeed(float speed)
	{
		speedVector = new Vector2(0, speed);
	}

	public void Explode(Color color)
	{
		for(int i=0; i< renderers.Length; i++)
			renderers[i].color = color;
		float xForce = Random.Range(-5f, 5f);
		float yForce = Random.Range(1, 5f);
		float rotForce = 2f * Mathf.Sign(xForce);
		_rigidbody.rotation = 0;
		_rigidbody.AddForce(new Vector2(xForce, yForce), ForceMode2D.Impulse);
		_rigidbody.AddTorque(-rotForce, ForceMode2D.Impulse);
		
		Invoke ("Destroy", 3f);
	}
	
	#endregion Functions

}