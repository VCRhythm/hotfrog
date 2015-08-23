using UnityEngine;
using System.Collections;
using DG.Tweening;
using TMPro;

public class Step : RigidbodySpawn {
	
	#region Public Fields
	
	public ActionType actionType;
    public float pullMultiplier = 1f;

    public Vector2 Position { get { return _transform.position; } set { _transform.position = value; } }
    public bool HasGuidance { get { return guidance != null; } }
	public bool IsUnsteady { get; private set; }
	public float TimeUnsteady { get { if(!IsUnsteady) return 0;	else return Time.time - unsteadyTime; }	}
	public System.Func<int, bool> canBeSpawned;
    [ReadOnly] public bool wasGrabbed = false;

    #endregion Public Fields

    #region Private Fields
	private Transform guidance = null;
	private Animator guidanceAnimator;
	
	private Vector2 savedPosition;
	private float savedAngularVelocity;
	private Vector2 pullPosition;
	private int grabbedPlayerID = -1;

	public enum ActionType
	{
		None,
		Crumble,
		CrumbleAfterRelease,
		Fall,
		ChangeDirectionUp,
		ChangeDirectionLeft,
		ChangeDirectionRight,
		ChangeDirectionUpRight,
		ChangeDirectionUpLeft,
		Launch,
		SlideOff,
		MakeFunky,
		MakeTarget,
		Move,
		RiseAndFall,
		Beetle,
		Castle,
		PullByLocation,
		Falling,
		SplashFlinging,
		StepFlinging,
		SpawnFly,
        Tutorial,
        Helper
	}
	private System.Action grabAction;
	private System.Action releaseAction;
	private System.Action fixedUpdate = () => {};
	private System.Action destroyAction = () => {};
		
	private float unsteadyTime = 0;
	//private const int ROCK_LAYER = 8;

	private ObjectPool pebblePool;
	private int explosionPebbles = 5;
	private int lavaSplashes = 4;
	private Lava lava;

	#endregion Private Fields

	#region Component Segments

	protected override void Awake()
	{
		base.Awake();

		lava = GameObject.FindObjectOfType<Lava>();
		pebblePool = GameObject.Find("PebbleSpawner").GetComponent<ObjectPool>();
	}

	protected override void OnEnable()
	{
		wasGrabbed = false;
		AssignInteractionAction();

        base.OnEnable();

        if (hasRotationFrozen)
            rb2D.MoveRotation(0);
        else
            rb2D.AddTorque(Random.Range(-350f, 350f), ForceMode2D.Impulse);
    }

    protected override void FixedUpdate ()
	{
        base.FixedUpdate();

        fixedUpdate();
	}

	protected override void OnTriggerEnter2D (Collider2D other)
	{
        if (!isDestroyableByBottomNet) // Used during the tutorial to prevent steps from disappearing if frog falls
            return;

        if (other.CompareTag("BottomNet"))
		{

			PlayCrumbleSound();
			lava.Splash(new Vector2(_transform.position.x, -50f), lavaSplashes);
			
			ForceRelease();
		}

		//else if(other.CompareTag("GrabableScenery")) return;
		
		base.OnTriggerEnter2D (other);
	}

	#endregion Component Segments

	#region Functions

	public void IntroShake()
	{
		for(int i=0; i< renderers.Length; i++)
		{
			renderers[i].DOFade(1, 1f);
		}
		_transform.DOShakePosition(1f, new Vector3(2, 2, 0), 20);
		_transform.DOShakeScale(1f);
	}

	public override void Grab(int playerID)
	{
		wasGrabbed = true;
		grabbedPlayerID = playerID;

		grabAction();
	}

	public void Release()
	{
		releaseAction();
		grabbedPlayerID = -1;
	}

    public override void FadeAndDestroy(float fadeDelay, float fadeTime, float destroyDelay)
    {
        destroyAction();

        base.FadeAndDestroy (fadeDelay, fadeTime, destroyDelay);		
	}

	public override void Destroy ()
	{
		destroyAction();

        base.Destroy ();
	}

/*	public void ShowGuidance(Transform guidancePrefab, bool canAlert = false)
	{
		if(HasGuidance) Destroy (guidance.gameObject);

		guidance = Instantiate (guidancePrefab, _transform.position, Quaternion.identity) as Transform;
		guidance.SetParent(_transform);

		if(canAlert)
		{
			Transform textAlert = guidance.FindChild("AlertText");
			textAlert.GetComponent<TextMeshPro>().text = "Hold on!";
			textAlert.DOLocalMoveX(-8f * Mathf.Sign (_transform.position.x), 0);
			textAlert.DOShakeScale(1f);
			AudioManager.Instance.Play(AudioManager.Instance.holdOnVoiceSound);
		}

		guidanceAnimator = guidance.GetComponent<Animator>();
	}

	public void ProgressGuidance()
	{
		if(HasGuidance)
		{
			guidanceAnimator.SetBool("isSelected", true);
		}
	}

	public void FinishGuidance()
	{
		if(HasGuidance)
		{
			guidanceAnimator.SetBool("isSelected", false);
			TextMeshPro holdText = guidance.GetComponentInChildren<TextMeshPro>();
			if(holdText != null)
				holdText.Clear ();
		}
	}

	public void DestroyGuidance()
	{
		if(guidance != null)
			Destroy(guidance.gameObject);
	}
    */
	#endregion Functions

	#region Private Functions

	private void MakeUnsteady(bool canFall, float delay)
	{
		IsUnsteady = true;
		unsteadyTime = Time.time;

		StartCoroutine(ShowCrumbles(delay));

		if(canFall)
			StartCoroutine("Fall");	
		else
			StartCoroutine("ReleaseUnsteadyTouch");
	}

	private IEnumerator ShowCrumbles(float delay)
	{
		yield return new WaitForSeconds(delay);
		while(IsUnsteady)
		{
			SpawnCrumbles();
			yield return new WaitForSeconds(1f);
		}
	}

	private IEnumerator ReleaseUnsteadyTouch()
	{
		yield return new WaitForSeconds(3f);

        if (IsUnsteady)
            ForceRelease();
	}

	private IEnumerator Fall()
	{
		yield return new WaitForSeconds(3f);

		if(IsUnsteady)
		{
			StopShakeTween();
			_transform.DOLocalMoveY(-100f, 1f);
		}
	}

	private void Pull(bool isInverted = false)
	{
        Invoke("StopPull", 1f);

        SpawnManager.Instance.PullStep(this, isInverted, pullMultiplier);
	}

	private void StopPull()
	{
		SpawnManager.Instance.ReleasePullingStep(this);
	}

/*	private void Pull()
	{	
		canMove = false;
		StopPullTween();

		savedPosition = _transform.position;
		SpawnManager.Instance.SetCommandingSpawn(this);
		_rigidbody.DOMove(_rigidbody.position + pullDest, 1f).OnUpdate(PullOtherSpawns).OnComplete(PullComplete);
	} */
/*
	private void PullOtherSpawns()
	{
		SpawnManager.Instance.SetPullVector(savedPosition - _rigidbody.position);
		savedPosition = _transform.position;
	}

	private void PullComplete()
	{
		SpawnManager.Instance.ReleaseCommandingSpawn(this);
	}
*/
	private void SetSpawnDirectionBasedOnPosition()
	{
		float xVal = rb2D.position.x < -5f ? 1f : (rb2D.position.x > 5f ? -1f : 0);
		float yVal = rb2D.position.y > 0f ? -1f : 0;

		SpawnManager.Instance.SpawnDirection = new Vector2( xVal, yVal);
	}

	private void SetSpawnDirectionBasedOnCastlePosition()
	{
		float xVal = rb2D.position.x < 0f ? 1f : -1f;
		float yVal = rb2D.position.y > 0f ? -1f : 0;

		SpawnManager.Instance.SpawnDirection = new Vector2( xVal, yVal);
	}

	private void InitialGrabAction()
	{	
		PlayGrabSound();

		Pull ();
        
        /*
		hasFixedAngle = _rigidbody.fixedAngle;
		savedAngularVelocity = _rigidbody.angularVelocity;
		_rigidbody.fixedAngle = true;

		if (HasGuidance)
		{
			ProgressGuidance();
		}
        */
	}
	
	private void InitialReleaseAction()
	{
		/*
        _rigidbody.fixedAngle = hasFixedAngle;
		if(!hasFixedAngle)
			_rigidbody.angularVelocity = savedAngularVelocity;

		if(HasGuidance)
		{
			DestroyGuidance();
		}
        */
	}

	private void Explode()
	{
		PlayShortCrumbleSound();
		SpawnCrumbles();
		DestroyIn(2f);
	}

	private void SpawnCrumbles()
	{
		for(int i=0; i <= explosionPebbles; i++)
		{
			pebblePool.GetTransformAndSetPosition(_transform.position).GetComponent<Pebble>().Explode(renderers[0].color);
		}
	}

	private void PlayShortCrumbleSound()
	{
		AudioManager.Instance.PlayForAll (AudioManager.Instance.crumbleShortSound, audioSource);
	}

	private void PlayCrumbleSound()
	{
		AudioManager.Instance.PlayForAll (AudioManager.Instance.crumbleSound, audioSource);
	}

	private void PlayGrabSound()
	{
		AudioManager.Instance.PlayForAll (AudioManager.Instance.grabSound, audioSource);
	}

	private void AssignInteractionAction()
	{
		grabAction = () => { InitialGrabAction(); };
		releaseAction = () => { InitialReleaseAction(); };
        canBeSpawned = (int spawnCount) => { return true; };
        destroyAction = () => { ForceRelease(); IsUnsteady = false; if (HasGuidance) Destroy(guidance.gameObject); };

		switch(actionType)
		{
            case ActionType.Tutorial:
                releaseAction += () => { Pull(true); };
                break;
		    case ActionType.Crumble:
			    grabAction += () => { MakeUnsteady(false, .5f); Invoke("Explode", 1.5f); };
			    break;
		    case ActionType.CrumbleAfterRelease:
			    releaseAction += () => { Explode(); };
			    break;
		    case ActionType.Fall:
			    grabAction += () => { MakeUnsteady(true, 1f); };
			    break;
		    case ActionType.ChangeDirectionLeft:
			    canBeSpawned = (int spawnCount) => { return SpawnManager.Instance.SpawnDirection != new Vector2(1, 0) && SpawnManager.Instance.SpawnDirection != new Vector2(-1, 0); };
			    grabAction = () => { SpawnManager.Instance.SpawnDirection = new Vector2(-1, 0); InitialGrabAction();};
			    break;
		    case ActionType.ChangeDirectionRight:
			    canBeSpawned = (int spawnCount) => { return SpawnManager.Instance.SpawnDirection != new Vector2(-1, 0) && SpawnManager.Instance.SpawnDirection != new Vector2(1, 0); };
			    grabAction = () => { SpawnManager.Instance.SpawnDirection = new Vector2(1, 0); InitialGrabAction();};
			    break;
		    case ActionType.ChangeDirectionUp:
			    canBeSpawned = (int spawnCount) => { return SpawnManager.Instance.SpawnDirection != new Vector2(0, -1); };
			    grabAction = () => { SpawnManager.Instance.SpawnDirection = new Vector2(0, -1);  InitialGrabAction();};
			    break;
		    case ActionType.ChangeDirectionUpLeft:
			    canBeSpawned = (int spawnCount) => { return SpawnManager.Instance.SpawnDirection != new Vector2(1, -1); };
			    grabAction = () => { SpawnManager.Instance.SpawnDirection = new Vector2(1, -1);  InitialGrabAction();};
			    break;
		    case ActionType.ChangeDirectionUpRight:
			    canBeSpawned = (int spawnCount) => { return SpawnManager.Instance.SpawnDirection != new Vector2(-1, -1); };
			    grabAction = () => { SpawnManager.Instance.SpawnDirection = new Vector2(-1, -1);  InitialGrabAction();};
			    break;
		    case ActionType.Beetle:
			    grabAction = () => { ForceRelease(); grabAction = () => { InitialGrabAction(); }; };
			    break;
		    case ActionType.PullByLocation:
			    grabAction = () => { SetSpawnDirectionBasedOnPosition(); InitialGrabAction(); };
			    break;
		    case ActionType.Falling:
			    canBeSpawned = (int spawnCount) => { return spawnCount > 5; };
			    fixedUpdate = () => { rb2D.AddForce(new Vector2(0, -50f), ForceMode2D.Force); };
			    break;
		    case ActionType.SplashFlinging:
			    GameObject splash = _transform.FindChild("Flingee").gameObject;
			    Vector2 splashLocalPosition = splash.transform.localPosition;
			    grabAction += () => { splash.GetComponent<Rigidbody2D>().isKinematic = false; splash.GetComponent<Splash>().enabled = true; };
			    destroyAction += () => { splash.GetComponent<Splash>().enabled = false; splash.GetComponent<Rigidbody2D>().isKinematic = true; splash.transform.localPosition = splashLocalPosition; splash.transform.localRotation = Quaternion.identity; };
			    break;

		    case ActionType.StepFlinging:
			    GameObject step = _transform.FindChild("Flingee").gameObject;
			    Vector2 stepLocalPosition = step.transform.localPosition;
			    grabAction += () => { step.GetComponent<Rigidbody2D>().isKinematic = false; step.GetComponent<Step>().enabled = true; };
			    destroyAction += () => { step.GetComponent<Step>().enabled = false; step.GetComponent<Rigidbody2D>().isKinematic = true; step.transform.localPosition = stepLocalPosition; step.transform.localRotation = Quaternion.identity; };
			    break;

		    case ActionType.SpawnFly:
			    GameObject bug = _transform.FindChild("Bug").gameObject;
			    Vector2 bugLocalPosition = bug.transform.localPosition;
			    grabAction += () => { bug.GetComponent<Bug>().enabled = true; };
			    destroyAction += () => { bug.GetComponent<Bug>().enabled = false; bug.transform.localPosition = bugLocalPosition; bug.transform.localRotation = Quaternion.identity; };
			    break;
		}
	}

    //	private void PullDownRelease()
    //	{
    //		StopPullTween();
    //	}

    private void ForceRelease()
    {
        CancelInvoke();
        ControllerManager.Instance.TellController(grabbedPlayerID, (x) => { x.ForceRelease(_transform); });
	}

	private IEnumerator DestroyIn(float delay)
	{
		yield return new WaitForSeconds(delay);
		Destroy ();
	}
	
//	private void StopPullTween()
//	{
//		if(DOTween.IsTweening(_transform))
//		{
//			_transform.DOKill();
//		}
//	}
	
	private void StopShakeTween()
	{
		IsUnsteady = false;
		StopCoroutine("ReleaseUnsteadyTouch");
		
		if(DOTween.IsTweening(1))
		{
			DOTween.Kill (1);
		}
	}

	#endregion Private Functions
}