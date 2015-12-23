using UnityEngine;

public abstract class Controller : MonoBehaviour {

    //Controller Variables
    public string controllerName;
    public int ControllerID { get; protected set; }
    public bool CanPlay { get ; set; }
    public bool IsPlaying { get; protected set; }

    //Input
    [ReadOnly] public bool canTouch = false;
    public bool CanTouch
    {
        get
        {
            if (frog == null || (canTouch && frog.isLowered))
            {
                return false;
            }
            else
            {
                return canTouch;
            }
        }
        set
        {
            canTouch = value;
        }
    }
    protected IUserInput UserInput;
    protected bool isTouchInput = false;
    LayerMask touchableLayerMask;

    //HUD Counters
    protected Vector4i grabStats;

    //Frog
    public Frog frog;
    protected FrogPackages frogPackages;

    //Limbs
    //int FreeLimbCount { get { return (limbs[0].IsFree ? 1 : 0) + (limbs[1].IsFree ? 1 : 0); } }
    protected Limb[] limbs = new Limb[2];
    protected bool HasStep { get { return !(limbs[0].IsFree && limbs[1].IsFree); } }
    protected bool HasFreeLimb { get { return limbs[0].IsFree || limbs[1].IsFree; } }
    Vector2[] limbReturnPos = new Vector2[2] { new Vector2(20, -40), new Vector2(-20, -40) };
    float limbReturnTime = .3f;
    Vector2[] currentLimbVelocity = new Vector2[2];

    protected virtual void Awake()
    {
        touchableLayerMask = LayerMask.GetMask("Touchable");
        frogPackages = GetComponent<FrogPackages>();
    }

    protected virtual void Start()
    {
        Register();
    }

    public void SetFrog(Frog frog)
    {
        this.frog = frog;
        frog.transform.name = controllerName + "'s Frog";
        frog.transform.SetParent(transform);
        limbs = frog.GetComponentsInChildren<Limb>();
        foreach (Limb limb in limbs)
        {
            limb.controllerID = ControllerID;
        }
    }

    public abstract void AteStartBug();

    public virtual void PlayLevel()
    {
        frog.Play();
        IsPlaying = true;
        CanTouch = true;
    }

    public abstract void CollectFly();

    public void ForceRelease(Transform step)
    {
        if (StepIsHeld(step))
        {
            FreeTouch(GetLimb(step).TouchIndex);
        }
    }

    private void Register()
    {
        ControllerID = ControllerManager.playerCount++;
        ControllerManager.Instance.Register(this);
    }

    protected void FreeUnusedTouches()
    {
        for (int i = 0; i < 2; i++)
        {
            if (!limbs[i].IsFree && (UserInput.InputCount <= limbs[i].TouchIndex || !UserInput.IsInputOn(limbs[i].TouchIndex)))
            {
                FreeTouch(i);
            }
        }
    }

    protected void FreeTouches()
    {
        for(int i = 0; i < 2; i++)
        {
            if(!limbs[i].IsFree)
            {
                FreeTouch(i);
            }
        }
    }

    protected void FreeTouch(int touchIndex)
    {
        //GetTouchIndicator(touchIndex).Hide();
        GetLimb(touchIndex).SetStep(null);
    }

    protected Limb GetFreeLimb()
    {
        if (limbs[0].IsFree)
            return limbs[0];
        else if (limbs[1].IsFree)
            return limbs[1];
        return null;
    }

    private Limb GetLimb(int touchIndex)
    {
        if (limbs[0].HasTouchIndex(touchIndex))
            return limbs[0];
        else if (limbs[1].HasTouchIndex(touchIndex))
            return limbs[1];
        return null;
    }

    private Limb GetLimb(Transform step)
    {
        if (limbs[0].GetStepTransform() == step)
            return limbs[0];
        else if (limbs[1].GetStepTransform() == step)
            return limbs[1];
        return null;
    }

    protected void MoveLimbs()
    {
        for (int i = 0; i < limbs.Length; i++)
        {
            //Move Limb to Step
            if (!limbs[i].IsFree && !limbs[i].IsMoving)
            {
                limbs[i].Position = limbs[i].GetStepTransform().position;
                limbs[i].HandRotation = limbs[i].GetStepTransform().rotation;
            }

            //Return Limb to starting location
            else
            {
                limbs[i].Position = Vector2.SmoothDamp(limbs[i].Position, limbReturnPos[i], ref currentLimbVelocity[i], limbReturnTime);
            }
        }
    }

    private bool StepIsHeld(Transform step)
    {
        return limbs[0].GetStepTransform() == step || limbs[1].GetStepTransform() == step;
    }

    protected void CheckTouch(Vector2 worldPos, int touchIndex)
    {
        RaycastHit2D hit = Physics2D.Raycast(worldPos, Vector2.zero, 1f, touchableLayerMask);

        //Touched an object
        if (hit.collider != null)
        {
            DecipherTouch(hit.transform, touchIndex, worldPos);
        }

        //Didn't touch an object
        else if (HasFreeLimb)
        {
            if (CanPlay)
            {
                //Miss
                //qualityText.GetTransformAndSetPosition(worldPos, 3);
                grabStats.w++;
            }
            AudioManager.Instance.PlayForAll(AudioManager.Instance.missSound);
            GetFreeLimb().Move(worldPos);

            frog.Look(worldPos);
        }
    }

    private void DecipherTouch(Transform touched, int touchIndex, Vector2 worldPos)
    {
        if (touched.CompareTag("Step") && HasFreeLimb && !StepIsHeld(touched))
        {
            TouchStep(touched, touchIndex, worldPos);
        }

        else if (touched.CompareTag("Bug"))
        {
            TouchBug(touched);
        }

        else if (touched.CompareTag("GrabableScenery"))
        {
            touched.SpawnScript().Grab(ControllerID);
        }

        frog.Look(touched);
    }

    private void TouchBug(Transform bug)
    {
        bug.BugSpawnScript().Grab(ControllerID);
        frog.ExpandTongue(bug);
    }

    protected virtual void TouchStep(Transform step, int touchIndex, Vector2 worldPos)
    {
        if (CanPlay && !step.StepSpawnScript().wasGrabbedControllerID[ControllerID])
        {
            step.StepSpawnScript().wasGrabbedControllerID[ControllerID] = true;
            float distance = (worldPos - (Vector2)step.position).sqrMagnitude;
            int index = distance > 20 ? 0 : (distance > 10 ? 1 : 2);
            TrackGrabQuality(index, worldPos);
        }

        Limb limb = GetFreeLimb();
        limb.SetStep(step, touchIndex);
    }

    protected virtual void TrackGrabQuality(int index, Vector2 worldPos)
    {
        if (index == 0)
        {
            grabStats.x++;
        }
        else if (index == 1)
        {
            grabStats.y++;
        }
        else if (index == 2)
        {
            grabStats.z++;
        }
    }

}