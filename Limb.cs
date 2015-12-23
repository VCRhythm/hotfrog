using UnityEngine;
using DG.Tweening;

public class Limb : MonoBehaviour {

    #region Fields

    public int controllerID = -1;

	private int touchIndex = -1;
	public int TouchIndex { get { return touchIndex; } set { touchIndex = value; } } 
	[HideInInspector]public float lastTouch = 0;

	public bool IsMoving { get; private set; }
	public bool IsFree { get { if(heldStep != null && stepGameObject.activeInHierarchy) return false; return true; } }

	public Vector2 Position { get { return transform.position; } set { transform.position = value; }}
	public Quaternion HandRotation { set { hand.rotation = value; } }
	private Transform hand;

	private SpriteRenderer handGrabRenderer;
	private SpriteRenderer handRenderer;

    [ReadOnly] public Transform heldStep;
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

		frog = transform.parent.GetComponent<Frog>();
		string handName = transform.name.Replace("Limb", "Hand");

		handRenderer = transform.FindChild(handName).GetComponent<SpriteRenderer>();
		originalSprite = handRenderer.sprite;

		hand = transform.FindChild(handName+"Grab");
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
			if(heldStep != null) OpenHand();
			stepScript = null;
            heldStep = null;
        }
		else
		{
			stepScript = newStep.StepSpawnScript();
			stepGameObject = newStep.gameObject;
            heldStep = newStep;
            Move(newStep);
		}
		
		touchIndex = newTouchIndex;		
	}

	public float TimeSinceGrab()
	{
		return GetStepScript().TimeUnsteady;
	}

	public Transform GetStepTransform()
	{
		return heldStep;
	}

	public Step GetStepScript()
	{
		return stepScript;
	}

    public void Move(Vector2 targetPosition)
	{
		CancelMovement();

		IsMoving = true;
        transform.DOMove(targetPosition, 0.1f).OnComplete(() => { IsMoving = false; });
	}
	
	#endregion Public Functions

	#region Private Functions

	private void Move(Transform target)
	{
		//Movement has already been cancelled by SetStep
		IsMoving = true;
        transform.DOMove((Vector2)target.position, 0.1f);
        Invoke("CloseHand", .1f);
	}

	private void CancelMovement()
	{
		if(DOTween.IsTweening(transform))
			transform.DOKill();
	}

	private void OpenHand()
	{
		handRenderer.sprite = originalSprite;
		//handGrabRenderer.sortingLayerName = ARMS_SORTING_LAYER;
		//handGrabRenderer.sortingOrder = 4;
		handGrabRenderer.sprite = null;

		if(heldStep != null && heldStep.gameObject.activeInHierarchy)
		{
			frog.StopBob(stepScript);
			stepScript.Release();
		}
	}
	
	private void CloseHand()
	{
        IsMoving = false;

        if (heldStep != null && stepScript.isActiveAndEnabled)
        {
            handGrabRenderer.sprite = grabSprite;
            handRenderer.sprite = backGrabSprite;
            //handGrabRenderer.sortingLayerName = ROCKS_SORTING_LAYER;
            //handGrabRenderer.sortingOrder = 1;

            frog.Bob(stepScript, heldStep.position.x);
            stepScript.Grab(controllerID);
        }
    }
	
	#endregion Private Functions
}
