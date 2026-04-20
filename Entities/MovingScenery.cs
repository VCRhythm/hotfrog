using UnityEngine;
using HotFrog.Audio;
using HotFrog.Spawning;
using HotFrog.Utility;

namespace HotFrog.Entities
{
public class MovingScenery : Spawn, IGrabable {

	[SerializeField] [RangeAttribute(0.5f,1)] private float minScale;
	[SerializeField] [RangeAttribute(1,2)] private float maxScale;
	[SerializeField] [RangeAttribute(1.5f, 2f)] private float minSpeedMod;
	[SerializeField] [RangeAttribute(4f,5f)] private float maxSpeedMod;
	[SerializeField] private Vector2 moveDirection;

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
		transform.localScale = new Vector3(scale, scale, 1);
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

		Destroy(0, 0, 1f);

		if(particles != null)
		{
			particles.Play();
		}
	}

	#endregion
}
}
