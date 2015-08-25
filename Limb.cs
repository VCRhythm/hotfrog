using UnityEngine;
using DG.Tweening;

public class Limb : MonoBehaviour {

    #region Fields

    public int playerID = -1;

	private int touchIndex = -1;
	public int TouchIndex { get { return touchIndex; } set { touchIndex = value; } } 
	[HideInInspector]public float lastTouch = 0;

	public bool IsMoving { get; private set; }
	public bool IsFree { get { if(step != null && stepGameObject.activeInHierarchy) return false; return true; } }

	private Transform _transform;
	public Vector2 Position { get { return _transform.position; } set { _transform.position = value; }}
	public Quaternion HandRotation { set { hand.rotation = value; } }
	private Transform hand;

	private SpriteRenderer handGrabRenderer;
	private SpriteRenderer handRenderer;

	private Transform step;
	private GameObject stepGameObject;
	private Step stepScript;

	[HideInInspector]public Sprite grabSprite;
	private Sprite backGrabSprite;
	private Sprite originalSprite;
	private Frog frog;
    private const string ARMS_SORTING_LAYER = "FrogArms";
	private const string ROCKS_SORTING_LAYER = "Rocks";

	#endregion Fields

	#region Component Segments

	void Awake()
	{
		IsMoving = false;

		_transform = transform;
		frog = _transform.parent.GetComponent<Frog>();
		string handName = _transform.name.Replace("Limb", "Hand");

		handRenderer = _transform.FindChild(handName).GetComponent<SpriteRenderer>();
		originalSprite = handRenderer.sprite;

		hand = _transform.FindChild(handName+"Grab");
		handGrabRenderer = hand.GetComponent<SpriteRenderer>();
		grabSprite = handGrabRenderer.sprite;
		backGrabSprite = (Sprite)frog.GetType().GetField(handName + "GrabBackSprite").GetValue(frog);
		handGrabRenderer.sprite = null;
	}

	#endregion Component Segments

	#region Public Functions

	public bool HasTouchIndex(int touchIndex)
	{
		if(this.touchIndex == touchIndex)
		{
			if(GetStepTransform() != null)
			{
				return true;
			}
			SetStep(null);
		}
		return false;
	}

	public void SetStep(Transform newStep, int newTouchIndex = -1)
	{
		CancelMovement();

		if(newStep == null)
		{
			if(step != null) OpenHand();
			stepScript = null;
            step = newStep;
        }
		else
		{
			stepScript = newStep.StepSpawnScript();
			stepGameObject = newStep.gameObject;
            step = newStep;
            MoveLimb(newStep);
		}
		
		touchIndex = newTouchIndex;		
	}

	public float TimeSinceGrab()
	{
		return GetStepScript().TimeUnsteady;
	}

	public Transform ReleaseStep()
	{
		Transform releasingStep = step;

		SetStep(null);

		return releasingStep;
	}

	public Transform GetStepTransform()
	{
		return step;
	}

	public Step GetStepScript()
	{
		return stepScript;
	}

	public void MoveLimb(Vector2 targetPosition)
	{
		CancelMovement();

		IsMoving = true;
        _transform.DOMove(targetPosition, 0.1f).OnComplete(MovingStopped);
	}
	
	#endregion Public Functions

	#region Private Functions

	private void MoveLimb(Transform target)
	{
		//Movement has already been cancelled by SetStep
		IsMoving = true;
        _transform.DOMove((Vector2)target.position, 0.1f).OnComplete(CloseHand);
	}

	private void CancelMovement()
	{
		if(DOTween.IsTweening(_transform))
			_transform.DOKill();
	}

	private void OpenHand()
	{
		handRenderer.sprite = originalSprite;
		//handGrabRenderer.sortingLayerName = ARMS_SORTING_LAYER;
		//handGrabRenderer.sortingOrder = 4;
		handGrabRenderer.sprite = null;

		if(step != null && step.gameObject.activeInHierarchy)
		{
			frog.StopBob(stepScript);
			stepScript.Release();
		}
	}
	
	private void CloseHand()
	{
		MovingStopped();

		handGrabRenderer.sprite = grabSprite;
		//handGrabRenderer.sortingLayerName = ROCKS_SORTING_LAYER;
		//handGrabRenderer.sortingOrder = 1;
		handRenderer.sprite = backGrabSprite;

    	frog.Bob(stepScript, step.position.x);
		stepScript.Grab(playerID);
	}

	private void MovingStopped()
	{
		IsMoving = false;
	}
	
	#endregion Private Functions
}
