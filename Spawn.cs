using UnityEngine;
using DG.Tweening;

public abstract class Spawn : PooledObject, IGrabable {

    [Range(0, 1)] public float spawnProbability = 1;
    public bool isDestroyableByBottomNet = true;
    public AudioClip grabClip;

    [HideInInspector] public SpriteRenderer[] renderers;
    [HideInInspector] public Vector3 originalScale;
    private Color[] originalRendererColors;
    protected virtual Vector2 speed { get { return SpawnManager.Instance.PullVector; } }
	protected AudioSource audioSource;

	#region Component Segments

	protected virtual void Awake()
	{
        transform.Register();
        originalScale = transform.localScale;

        audioSource = GetComponent<AudioSource>();

		renderers = GetComponentsInChildren<SpriteRenderer>();
		originalRendererColors = new Color[renderers.Length];
		for(int i=0; i< renderers.Length; i++) originalRendererColors[i] = renderers[i].color;
	}
	
	protected virtual void OnTriggerEnter2D(Collider2D other)
	{
		Destroy ();
	}

	#endregion Component Segments

	public virtual void Destroy(float fadeDelay, float fadeTime, float destroyDelay)
	{
		Invoke ("Destroy", destroyDelay);
	}

	public override void Destroy()
	{
		for(int i = 0; i < renderers.Length; i++)
		{
			renderers[i].color = originalRendererColors[i];
		}

        if (Pool != null)
        {
            Pool.Insert(gameObject);
        }
        else
        {
            transform.DOKill();
            Destroy(gameObject);
        }
	}
	
	public virtual void PauseMovement(){}
	public virtual void ResumeMovement(){}

	#region IGrabable implementation
	public virtual void Grab (int playerID) { }
	#endregion
}