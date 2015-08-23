using UnityEngine;

public class MovingScenery : Spawn, IGrabable {
	
	[RangeAttribute(0.5f,1)]public float minScale;
	[RangeAttribute(1,2)]public float maxScale;
	[RangeAttribute(1.5f, 2f)]public float minSpeedMod;
	[RangeAttribute(4f,5f)]public float maxSpeedMod;
	public Vector2 moveDirection;

	Rigidbody2D rb2D;
	float speedModifier;
	ParticleSystem particles;
	bool canGrab = true;

	#region Component Segments
	
	protected override void Awake ()
	{
		base.Awake ();

		particles = GetComponent<ParticleSystem>();
		rb2D = GetComponent<Rigidbody2D>();
	}
	
	void FixedUpdate()
	{
		rb2D.AddForce(moveDirection * speedModifier);
	}
	
	void OnEnable()
	{
		canGrab = true;
		speedModifier = Random.Range(minSpeedMod, maxSpeedMod);
		
		float scale = Random.Range(minScale, maxScale);
		_transform.localScale = new Vector3(scale, scale, 1);
	}

	protected override void OnTriggerEnter2D (Collider2D other)
	{
		return;
	}
	
	#endregion Component Segments

	#region IGrabable implementation

	public override void Grab (int playerID) 
	{ 
		if(!canGrab) return;

		canGrab = false;

		if(grabClip != null) 
		{
			AudioManager.Instance.PlayForAll(grabClip, audioSource);
		}

		FadeAndDestroy(0, 0, 1f);

		if(particles != null)
		{
			particles.Play();
		}
	}

	#endregion
}