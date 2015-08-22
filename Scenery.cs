using UnityEngine;

public class Scenery : RigidbodySpawn {

    public Vector2 autoMovementMin = Vector2.zero;
    public Vector2 autoMovementMax = Vector2.zero;
    private Vector2 autoMovement = Vector2.zero;

    public bool hasMaterial = false;

    protected override Vector2 speed { get { return (base.speed == Vector2.zero) ? autoMovement : base.speed * speedModifier; } }

    #region Component Segments

    protected override void Awake ()
	{
		base.Awake ();
        
        originalScale = _transform.localScale;
	}
	
    protected override void OnEnable()
    {
        base.OnEnable();

        autoMovement = new Vector2(Random.Range(autoMovementMin.x, autoMovementMax.x), Random.Range(autoMovementMin.y, autoMovementMax.y));
    }

	protected override void FixedUpdate()
	{
        base.FixedUpdate();
    }

    private void PlayAudio()
    {
        AudioManager.Instance.Play(null, audioSource);
    }

	#endregion Component Segments

}