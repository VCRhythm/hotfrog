using UnityEngine;
using System.Collections;
using DG.Tweening;
using System.Collections.Generic;

public class Frog : MonoBehaviour {
	
	//Purchase Information
	[Range(1, 20)] public int id;
	public string frogName;
	[Range(0, 1)] public int isUnlocked = 0;
	[Range(0, 1)] public int canBuy = 1;
	//public Material crazyMaterial;

	// Eye Sprites
	private enum EyelidState
	{
		Open,
		Low,
		Lower,
		Closed
	}
	
	private enum RiseState
	{
		Lowered,
		Peeking,
		Arisen,
		Unlocked
	}
	[HideInInspector] public bool isFalling = false;
	[HideInInspector] public bool isDead = false;
    [HideInInspector] public bool canDie = false;
    
    public AudioClip audioIntroduction;
	public List<SpriteLoad> spriteLoads = new List<SpriteLoad>();
	private Sprite RightHandGrabSprite;
	private Sprite LeftHandGrabSprite;

	[HideInInspector] public Sprite ThumbnailSprite;
    [HideInInspector]
    public Material ThumbnailMaterial;
	[HideInInspector] public Sprite LowRightEyelidSprite;
    [HideInInspector]
    public Material LowRightEyelidMaterial;
    [HideInInspector] public Sprite LowLeftEyelidSprite;
    [HideInInspector]
    public Material LowLeftEyelidMaterial;
    [HideInInspector] public Sprite LowerRightEyelidSprite;
    [HideInInspector]
    public Material LowerRightEyelidMaterial;
    [HideInInspector] public Sprite LowerLeftEyelidSprite;
    [HideInInspector]
    public Material LowerLeftEyelidMaterial;
    [HideInInspector] public Sprite ClosedRightEyelidSprite;
    [HideInInspector]
    public Material ClosedRightEyelidMaterial;
    [HideInInspector] public Sprite ClosedLeftEyelidSprite;
    [HideInInspector]
    public Material ClosedLeftEyelidMaterial;
    [HideInInspector] public Sprite RightHandGrabBackSprite;
    [HideInInspector]
    public Material RightHandGrabBackMaterial;
    [HideInInspector] public Sprite LeftHandGrabBackSprite;
    [HideInInspector]
    public Material LeftHandGrabBackMaterial;

    private float lastBlink = 0;
	private float minBlinkTime = 1f;
	private float maxBlinkTime = 3f;
	private bool isDrugged = false;

	private float druggedTime = 2f;
	private float druggedStart = 0;
	private SpriteRenderer leftScleraRenderer;
	private SpriteRenderer rightScleraRenderer;
	private SpriteRenderer leftEyelidRenderer;
	private SpriteRenderer rightEyelidRenderer;
	private Vector2 leftPupilPosition;
	private Vector2 rightPupilPosition;
	private Transform leftPupil;
	private Transform rightPupil;
	private float pupilClamp = 3f;
	private Transform lookTargetTransform;
	private bool hasLookTarget = false;
	private Vector2 lookTarget = Vector2.zero;
	private Vector2 RightLookTarget { get { 
			Vector2 point;
			if(lookTargetIsTransform && lookTargetTransform != null) 
			{
				point = (Vector2)rightPupil.InverseTransformPoint(lookTargetTransform.position) - rightPupilPosition; 
			}
			else 
			{
				point = lookTarget - rightPupilPosition;
			}
			return new Vector2(Mathf.Clamp(point.x, -pupilClamp, pupilClamp), Mathf.Clamp(point.y, -pupilClamp, pupilClamp));
		} 
	}
	private Vector2 LeftLookTarget { get { 
			Vector2 point;
			if(lookTargetIsTransform && lookTargetTransform != null) 
			{
				point = (Vector2)leftPupil.InverseTransformPoint(lookTargetTransform.position) - leftPupilPosition; 
			}
			else 
			{
				point = lookTarget - leftPupilPosition;
			}
			return new Vector2(Mathf.Clamp(point.x, -pupilClamp, pupilClamp), Mathf.Clamp(point.y, -pupilClamp, pupilClamp));
		} }

	private bool lookTargetIsTransform = false;
	private Vector2 leftPupilVelocity;
	private Vector2 rightPupilVelocity;

//	private Material originalMaterial;
//	private MeshRenderer backgroundRenderer;
//	private Animation backgroundAnimation;

	private Transform _transform;
	private Transform headTransform;
	public Tongue tongue { get; private set; }

	private float gravity = 20f;
	private float gravityMultiplierStart = 0.5f;
	private float gravityMultiplier;
	private float gravityAcceleration = .02f;
	private Step bobStep;
	private Step BobStep { get { return bobStep; } set { bobStep = value;}}
		
    private bool isMoving = false;
	private RiseState riseState = RiseState.Lowered;

	public Vector2 BodyPosition { get { return _transform.position; } set { _transform.position = new Vector2(value.x, value.y);}}
	public Vector2 HeadPosition { get { return headTransform.localPosition; } set { headTransform.localPosition = new Vector2(value.x, value.y); } }

	//Timers
	private WaitForSeconds blinkAnimateCounter = new WaitForSeconds(.05F);
	private WaitForFixedUpdate fixedUpdateTimer = new WaitForFixedUpdate();
	private WaitForSeconds druggedTimer = new WaitForSeconds(0.1F);
	private WaitForSeconds minBlinkTimer;

	//Fall Variables
	private float smoothTime = .3f;
	private float yVelocity = 0f;
	private float endY = -100f;

    void Awake()
	{
		_transform = transform;

		minBlinkTimer = new WaitForSeconds(minBlinkTime);

		headTransform = _transform.FindChild("Head");
		tongue = headTransform.FindChild("Tongue").GetComponent<Tongue>();
		rightPupil = headTransform.FindChild("RightPupil");
		leftPupil = headTransform.FindChild("LeftPupil");

		rightEyelidRenderer = headTransform.FindChild("RightEyelid").GetComponent<SpriteRenderer>();
		leftEyelidRenderer = headTransform.FindChild("LeftEyelid").GetComponent<SpriteRenderer>();

		rightScleraRenderer = headTransform.FindChild("RightSclera").GetComponent<SpriteRenderer>();
		leftScleraRenderer = headTransform.FindChild("LeftSclera").GetComponent<SpriteRenderer>();

		rightPupilPosition = headTransform.FindChild("RightPupilPosition").localPosition;
		leftPupilPosition = headTransform.FindChild("LeftPupilPosition").localPosition;
	}

	void Update()
	{
		if(hasLookTarget)
		{
			rightPupil.localPosition = Vector2.SmoothDamp(rightPupil.localPosition, RightLookTarget, ref rightPupilVelocity, .3f);
			leftPupil.localPosition = Vector2.SmoothDamp(leftPupil.localPosition, LeftLookTarget, ref leftPupilVelocity, .3f);
		}
		else
		{
			rightPupil.localPosition = Vector2.SmoothDamp(rightPupil.localPosition, Vector2.zero, ref rightPupilVelocity, .3f);
			leftPupil.localPosition = Vector2.SmoothDamp(leftPupil.localPosition, Vector2.zero, ref leftPupilVelocity, .3f);
		}
	}

    public void Play()
    {
        Reset();
        SlowlyLower();
    }

	public void EndGame(bool hasDied)
	{
		if(hasDied)
		{
            Die();
		}
		else
		{
			Rise(true, 0, true);
		}
	}

	public void MakeDrugged()
	{
		if(isDrugged)
		{
			StopCoroutine("Drugged");
		}
		isDrugged = true;
		StartCoroutine("Drugged");
	}

	public void WakeUp()
	{
        StartCoroutine (AwakeAnimate());
	}

	public void Rise(bool canFullyRise, float delay = 0, bool canPlaySound = true)
	{
		if(riseState != RiseState.Arisen)
		{
			StopCoroutine("SteadilyLowerHead");

			ResetLook();

			riseState = canFullyRise ? RiseState.Arisen : RiseState.Peeking;

			if(canPlaySound) AudioManager.Instance.PlayIn(delay, AudioManager.Instance.awakeSound);
			headTransform.DOLocalMove(canFullyRise ? Vector2.zero : new Vector2(0, endY /2), .5f).SetDelay(delay);
			_transform.DOMoveY(0, 1f).SetDelay(delay);
		}
	}

	public void Lower()
	{
		if(riseState != RiseState.Lowered)
		{
			riseState = RiseState.Lowered;
			_transform.DOMoveY (endY, 1f);
		}
	}
	
	public void Bob(Step step, float xVal)
	{
		gravityMultiplier = gravityMultiplierStart;

		isMoving = true;
		BobStep = step;

		float yDest = Mathf.Min(5f, HeadPosition.y + 50f);
		//float xDest = Mathf.Sign(HeadPosition.x == 0 ? xVal : -HeadPosition.x) * 5f;
		float xDest = xVal;
		float xDestTime = Mathf.Abs(xDest - HeadPosition.x) * 0.06f;
		float yDestTime = Mathf.Abs(yDest - HeadPosition.y) * 0.05f;

		if(Mathf.Sign(xDest) == Mathf.Sign(xVal))
		{
			DOTween.Kill ("X");
            //DOTween.Kill("XRock");
            headTransform.DOPunchRotation(new Vector3(0, 0, -0.1f * (headTransform.position.x - xDest)), 1f, 1, 1f).SetId("XRock").OnComplete(() => { headTransform.DORotate(Vector3.zero, 1f); } );
			headTransform.DOMoveX(xDest, xDestTime).SetEase(Ease.OutSine).SetId("X");
		}

		if(HeadPosition.y <= -5f && !DOTween.IsTweening("Y"))
		{
			headTransform.DOMoveY(yDest, yDestTime).SetEase(Ease.OutSine).SetId("Y");
		}
	}
	
	public void StopBob(Step step)
	{
		if(isMoving && BobStep == step)
		{
			BobStep = null;
			isMoving = false;
			DOTween.Kill("Y");
		}
    }	

	public void ExpandTongue(Transform target)
	{
		tongue.Expand(target);
	}

	public void Look(Transform target)
	{
		hasLookTarget = true;
		//ShowEyes(EyelidState.Open);
		lookTargetTransform = target;
		lookTargetIsTransform = true;
	}

	public void Look(Vector2 target)
	{
		hasLookTarget = true;
		//ShowEyes(EyelidState.Open);
		lookTargetIsTransform = false;
		lookTarget = rightPupil.InverseTransformPoint(target);
	}

#if UNITY_EDITOR
	public void AddSpriteLoad(SpriteRenderer renderer)
	{
		spriteLoads.Add(new SpriteLoad(frogName, renderer));
	}

	public void AddSpriteLoad(string variableName)
	{
		spriteLoads.Add (new SpriteLoad(frogName, variableName));
	}
#endif

    #region Private Functions

    private void Reset()
    {
        ResetLook();
        isDead = false;
        isFalling = false;
        isMoving = false;
    }

    private void SlowlyLower()
    {
        StopCoroutine("SteadilyLowerHead");
        riseState = RiseState.Unlocked;
        Look(Vector2.up * 100f);
        gravityMultiplier = gravityMultiplierStart;
        StartCoroutine("SteadilyLowerHead");
    }

    private void CancelBob()
	{
		if(DOTween.IsTweening(headTransform)) headTransform.DOKill();
	}
	
	private IEnumerator Drugged()
	{
		druggedStart = Time.time;
	
		//backgroundRenderer.sharedMaterial = crazyMaterial;
		//backgroundAnimation.Play();

		while(Time.time - druggedStart < druggedTime)
		{
			leftScleraRenderer.color = new Vector4(Random.Range(0,1f), Random.Range(0,1f), Random.Range(0,1f), 1);
			rightScleraRenderer.color = new Vector4(Random.Range(0,1f), Random.Range(0,1f), Random.Range(0,1f), 1);
			yield return druggedTimer;
		}

		//backgroundRenderer.sharedMaterial = originalMaterial;
		//backgroundAnimation.Stop();
		leftScleraRenderer.color = new Vector4(1, 1, 1, 1);
		rightScleraRenderer.color = new Vector4(1, 1, 1, 1);
		isDrugged = false;
	}
	
	private IEnumerator Blink()
	{
		while(true)
		{
			yield return minBlinkTimer;
			if(Time.time - lastBlink > Random.Range(minBlinkTime, maxBlinkTime))
			{
				StartCoroutine(BlinkAnimate());
				lastBlink = Time.time;
			}
		}
	}

	private IEnumerator AwakeAnimate()
	{
		ShowEyes (EyelidState.Lower);
		yield return blinkAnimateCounter;

		ShowEyes(EyelidState.Low);
		yield return blinkAnimateCounter;

		ShowEyes(EyelidState.Open);
		yield return blinkAnimateCounter;

		StartCoroutine(Blink ());
	}

	private IEnumerator BlinkAnimate()
	{
		if(!isDrugged)
		{
			ShowEyes(EyelidState.Low);
			yield return blinkAnimateCounter;
		}

		ShowEyes (EyelidState.Lower);
		yield return blinkAnimateCounter;

		ShowEyes (EyelidState.Closed);
		yield return blinkAnimateCounter;

		ShowEyes (EyelidState.Lower);
		yield return blinkAnimateCounter;

		ShowEyes(EyelidState.Low);
		yield return blinkAnimateCounter;

		if(!isDrugged)
		{
			ShowEyes(EyelidState.Open);
			yield return blinkAnimateCounter;
		}
	}

	private void ShowEyes(EyelidState eyeState)
	{
		switch(eyeState)
		{
		case EyelidState.Closed:
			leftEyelidRenderer.sprite = ClosedLeftEyelidSprite;
			rightEyelidRenderer.sprite = ClosedRightEyelidSprite;
			break;
		case EyelidState.Low:
			leftEyelidRenderer.sprite = LowLeftEyelidSprite;
			rightEyelidRenderer.sprite = LowRightEyelidSprite;
			break;
		case EyelidState.Lower:
			leftEyelidRenderer.sprite = LowerLeftEyelidSprite;
			rightEyelidRenderer.sprite = LowerRightEyelidSprite;
			break;
		case EyelidState.Open:
			leftEyelidRenderer.sprite = null;
			rightEyelidRenderer.sprite = null;
			break;
		}
	}
	
	private IEnumerator SteadilyLowerHead()
	{
		isFalling = true;

		while(!isDead)
		{
			if(isFalling && HeadPosition.y > -50) 
			{
				gravityMultiplier += gravityAcceleration;
				headTransform.Translate(0, -gravity * gravityMultiplier * Time.deltaTime, 0, Space.World);
			}
			yield return fixedUpdateTimer;
		}
	}

	private IEnumerator Fall()
	{
		riseState = RiseState.Lowered;
		CancelBob();
		
		yield return new WaitForSeconds(1f);
		
		PlayFallSound();

		while(BodyPosition.y > endY + 1)
		{
			float newY = Mathf.SmoothDamp (BodyPosition.y, endY, ref yVelocity, smoothTime);
			BodyPosition = new Vector2(BodyPosition.x, newY);
			yield return fixedUpdateTimer;
		}

		Rise (false, 1f, false);
	}
	
	private void PlayFallSound()
	{
		AudioManager.Instance.PlayForAll(AudioManager.Instance.fallSound);
	}

	private void ResetLook()
	{
		hasLookTarget = false;
	}

    private void Die()
    {
        isDead = true;
        StartCoroutine(Fall());
    }
	
	#endregion Private Functions
}
