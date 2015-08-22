using UnityEngine;
using System.Collections.Generic;

public class TouchManager : MonoBehaviour {

	// A singleton instance of this class
	private static TouchManager instance;
	public static TouchManager Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<TouchManager>();
			return instance;
		}
	}

	#region Fields
    
	[HideInInspector] public bool canDie = false;
	[HideInInspector] public bool isPlaying = false;

	//HUD Counters
	Vector4i grabStats;
	
	//Limbs
	Limb[] limbs = new Limb[2];
	public int FreeLimbCount { get { return (limbs[0].IsFree ? 1 : 0) + (limbs[1].IsFree ? 1 : 0); } }
	bool HasFreeLimb { get { return limbs[0].IsFree || limbs[1].IsFree; } }
	bool HasStep { get { return !(limbs[0].IsFree && limbs[1].IsFree); } }
	Vector2[] limbReturnPos = new Vector2[2]{new Vector2(20, -40), new Vector2(-20, -40)};
	float limbReturnTime = .3f;
	Vector2[] currentLimbVelocity = new Vector2[2];

	//Input
	bool isTouchInput = false;
	[HideInInspector] public bool canTouch = false;
	TouchIndicator[] touchIndicators = new TouchIndicator[2];
	delegate void TouchStepAction(Transform touched, int touchIndex, Vector2 worldPos);
	TouchStepAction touchStepAction;
	IUserInput UserInput;
    LayerMask touchableLayerMask;

    //Guidance
    public TouchIndicator touchIndicatorPrefab;
    public Transform[] guidancePrefabs = new Transform[2];

    //Components
    [HideInInspector] public Frog frog;
    CanvasGroup endGameCanvas;
    ObjectPool qualityText;
        
    #endregion Fields

    #region Component Segments

    void Awake()
	{
        touchableLayerMask = LayerMask.GetMask("Touchable");
		SetUpInput();
		SetUpTouchIndicators();

		touchStepAction = TouchStep;

		qualityText = GetComponent<ObjectPool>();
    }
	
	void Update ()
	{
        if (canTouch)
        {
            MoveLimbs();

            if (Input.GetKeyDown(KeyCode.Z))
            {
                //Debug.Log ((limbs[0].GetStepScript() ? limbs[0].GetStepScript().transform.name : "None") + ", " + (limbs[1].GetStepScript() ? limbs[1].GetStepScript().transform.name : "None"));
                //Debug.Break();
                Application.CaptureScreenshot("test.png", 4);
            }

            for (int i = 0; i < UserInput.InputCount; i++)
            {

                if (UserInput.HasInputStarted(i))
                {
                    Vector2 worldPosition = Camera.main.ScreenToWorldPoint(UserInput.GetPosition(i));

                    if (isTouchInput)
                        IncrementOtherTouchIndices(i);

                    CheckTouch(worldPosition, i);

                    //					if(TouchIsLimb(i))
                    //					{
                    //						if(GetNewTouchIndicator(i) == null) Debug.Break();
                    //						Debug.Log (GetNewTouchIndicator(i));
                    //						GetNewTouchIndicator(i).Show(i, GetLimb(i).grabSprite);
                    //					}
                }

                //				if(UserInput.IsInputOn(i))
                //				{
                //					if(TouchIsLimb(i))
                //					{
                //						TouchIndicator indicator = GetTouchIndicator(i);
                //						indicator.SetPosition(Camera.main.ScreenToWorldPoint(UserInput.GetPosition (i)));
                //					}
                //				}
                if (!UserInput.IsInputOn(i))
                {
                    if (TouchIsLimb(i))
                    {
                        FreeTouch(i);
                    }

                    if (isTouchInput)
                        DecrementOtherTouchIndices(i);
                }
            }

            for (int i = 0; i < 2; i++)
            {
                if (!limbs[i].IsFree && (UserInput.InputCount <= limbs[i].TouchIndex || !UserInput.IsInputOn(limbs[i].TouchIndex)))
                {
                    FreeTouch(i);
                }
            }
                
			if(!frog.IsDead && canDie && !HasStep)
			{
                if (LevelManager.Instance.isInvincibleLevel)
                {
                    LevelManager.Instance.ResetInvincibleLevel();
                    AudioManager.Instance.Play(AudioManager.Instance.fallSound);
                    SetCanDie(false);
                }
                else
                {
                    EndGame();
                }
			}
		}

	}
	
	#endregion Component Segments

	#region Functions
	
	public void StartLevel()
	{
		ResetGame();
	}
	
	public void ReleaseStep(Transform step)
	{
		if(StepIsHeld(step))
		{
			FreeTouch(GetLimb(step).TouchIndex);
		}
	}

	public void SetFrog(Transform newFrog)
	{
		frog = newFrog.GetComponent<Frog>();
		limbs = newFrog.GetComponentsInChildren<Limb>();
	}
	
	public void EndGame(bool hasDied = true, bool canAdvanceLevel = false)
	{
        if (hasDied) canTouch = false;
        isPlaying = false;
        SetCanDie(false);

        HideTouchIndicators();
		MenuManager.Instance.SetGrabStats(grabStats);
		LevelManager.Instance.EndLevel(hasDied, canAdvanceLevel);

		if(!canAdvanceLevel)
            frog.EndGame(hasDied);
	}

	#endregion Functions

	#region Private Functions
	
	private TouchIndicator GetTouchIndicator(int touchIndex)
	{
		if(touchIndicators[0].touchIndex == touchIndex) return touchIndicators[0];
		if(touchIndicators[1].touchIndex == touchIndex) return touchIndicators[1];
		return null;
	}

	private void DecrementOtherTouchIndices(int touchIndex)
	{
		DecrementLimbTouchIndices(touchIndex);
		DecrementIndicatorTouchIndices(touchIndex);
	}

	private void DecrementLimbTouchIndices(int touchIndex)
	{
		if(limbs[1].TouchIndex > touchIndex)
			limbs[1].TouchIndex--;
		else if(limbs[0].TouchIndex > touchIndex)
			limbs[0].TouchIndex--;
	}

	private void DecrementIndicatorTouchIndices(int touchIndex)
	{
		if(touchIndicators[1].touchIndex > touchIndex)
			touchIndicators[1].touchIndex--;
		else if(touchIndicators[0].touchIndex > touchIndex)
			touchIndicators[0].touchIndex--;
	}

	private void IncrementOtherTouchIndices(int touchIndex)
	{
		IncrementLimbTouchIndices(touchIndex);
		IncrementIndicatorTouchIndices(touchIndex);
	}

	private TouchIndicator GetNewTouchIndicator(int touchIndex)
	{
		if(touchIndicators[0].IsUnused) return touchIndicators[0];
		if(touchIndicators[1].IsUnused) return touchIndicators[1];
		return null;
	}

	private void IncrementLimbTouchIndices(int touchIndex)
	{
		if(limbs[1].TouchIndex >= touchIndex) 
			limbs[1].TouchIndex++;
		else if(limbs[0].TouchIndex >= touchIndex)
			limbs[0].TouchIndex++;
	}

	private void IncrementIndicatorTouchIndices(int touchIndex)
	{
		if(touchIndicators[1].touchIndex >= touchIndex) 
			touchIndicators[1].touchIndex++;
		else if(touchIndicators[0].touchIndex >= touchIndex)
			touchIndicators[0].touchIndex++;
	}

	private void FreeTouch(int touchIndex)
	{
//		GetTouchIndicator(touchIndex).Hide();
		GetLimb(touchIndex).ReleaseStep();
	}
			
	private void SetUpBarriers()
	{
		float halfScreenWidth = 50 * ((float)Screen.width / Screen.height);

		GameObject.Find("LeftRockBarrier").transform.position = new Vector2(-halfScreenWidth-1, -1.8f);
		GameObject.Find("RightRockBarrier").transform.position = new Vector2(halfScreenWidth+1, -1.8f);
	}
	
	private void CheckTouch(Vector2 worldPos, int touchIndex)
	{
		RaycastHit2D hit = Physics2D.Raycast (worldPos, Vector2.zero, 1f, touchableLayerMask);

		//Touched an object
		if(hit.collider != null)
		{
			DecipherTouch(hit.transform, touchIndex, worldPos);
		}

		//Didn't touch an object
		else if(HasFreeLimb)
		{
			if(isPlaying)
			{
				//qualityText.GetTransformAndSetPosition(worldPos, 3);
				grabStats.w++;
			}
			AudioManager.Instance.Play(AudioManager.Instance.missSound);
			GetFreeLimb().MoveLimb(worldPos);

			frog.Look(worldPos);
		}
	}

	private void DecipherTouch(Transform touched, int touchIndex, Vector2 worldPos)
	{
		if(touched.CompareTag("Step") && HasFreeLimb && !StepIsHeld(touched))
		{
			touchStepAction(touched, touchIndex, worldPos);
		}

		else if(touched.CompareTag("Bug"))
		{
			TouchBug(touched);
		}

		else if(touched.CompareTag("GrabableScenery"))
		{
			touched.SpawnScript().Grab();
		}

		frog.Look(touched);
	}

	private void TouchBug(Transform bug)
	{
		bug.BugSpawnScript().Grab();
		frog.ExpandTongue(bug);
	}

	private void TouchStep(Transform step, int touchIndex, Vector2 worldPos)
    { 
		if(isPlaying && !step.StepSpawnScript().wasGrabbed)
		{
			float distance = (worldPos - (Vector2)step.position).sqrMagnitude;
			int index = distance > 20 ? 0 : (distance > 10 ? 1 : 2);
			TrackGrabQuality(index);
			qualityText.GetTransformAndSetPosition(worldPos, index);
            HUD.Instance.StepsClimbed++;
        }

        Limb limb = GetFreeLimb();
		limb.SetStep(step, touchIndex);

        LevelManager.Instance.CheckForStepTrigger(step, HUD.Instance.StepsClimbed);
	}

/*	private void TouchStepEnhanced(Transform step, int touchIndex)
	{
		Limb otherLimb = GetLimb( (touchIndex == 0) ? 1 : 0);
		Step thisStepScript = step.StepSpawnScript();

		if(otherLimb != null && ((otherLimb.GetStepScript().typeID == -1 || thisStepScript.typeID == -1) || thisStepScript.typeID == otherLimb.GetStepScript().typeID) )
		{
			Beam beam = Instantiate(beamPrefab, otherLimb.GetStepTransform().position, Quaternion.identity) as Beam;
			beam.Expand(otherLimb.GetStepTransform(), step, otherLimb.GetStepScript().color);

			otherLimb.GetStepScript().Explode();

			AudioManager.Instance.Play(AudioManager.Instance.newSound);

			if(++stepsLinked > StepsClimbed) StepsClimbed = stepsLinked;
		}
		else if(!thisStepScript.isUnsteady)
			stepsLinked = 0;
	}
	*/
				
	private bool StepIsHeld(Transform step)
	{
		return limbs[0].GetStepTransform() == step || limbs[1].GetStepTransform() == step;
	}
	
	private Limb GetFreeLimb() 
	{ 
		if(limbs[0].IsFree)
			return limbs[0];
		else if(limbs[1].IsFree)
			return limbs[1];
		return null;
	} 

	private Limb GetLimb(int touchIndex)
	{
		if(limbs[0].HasTouchIndex(touchIndex))
			return limbs[0];
		else if(limbs[1].HasTouchIndex(touchIndex))
			return limbs[1];
		return null;
	}

	private Limb GetLimb(Transform step)
	{
		if(limbs[0].GetStepTransform() == step)
			return limbs[0];
		else if(limbs[1].GetStepTransform() == step)
			return limbs[1];
		return null;
	}

	private bool TouchIsLimb(int touchIndex)
	{
		return limbs[0].HasTouchIndex(touchIndex) || limbs[1].HasTouchIndex(touchIndex);
	}
	
	private void SetUpTouchIndicators()
	{
		for(int i = 0; i < touchIndicators.Length; i++)
		{
			touchIndicators[i] = Instantiate(touchIndicatorPrefab) as TouchIndicator;
		}
	}

	private void HideTouchIndicators()
	{
		for(int i = 0; i < touchIndicators.Length; i++)
			touchIndicators[i].Hide();
	}

	private void MoveLimbs()
	{
		for(int i = 0; i < limbs.Length; i++)
		{
			//Move Limb to Step
			if(!limbs[i].IsFree && !limbs[i].IsMoving)
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

	private void TrackGrabQuality(int index)
	{
		if(index == 0)
		{
			AudioManager.Instance.Play(AudioManager.Instance.okVoiceSound);
			grabStats.x++;
		}
		else if(index == 1)
		{
			AudioManager.Instance.Play(AudioManager.Instance.greatVoiceSound);
			grabStats.y++;
		}
		else if(index == 2)
		{
			AudioManager.Instance.Play(AudioManager.Instance.perfectVoiceSound);
			grabStats.z++;
		}
	}

	private void ResetGame()
	{
		canTouch = true;
		isPlaying = true;
		HUD.Instance.SetInitialStats();
		grabStats = Vector4i.zero;
		frog.Reset();
	}
		
	private void SetUpInput()
	{
#if UNITY_EDITOR
		Component[] userInputs = GetComponents (typeof(IUserInput));
		UserInput = (userInputs[0] as IUserInput).IsTouchInput ? userInputs[1] as IUserInput : userInputs[0] as IUserInput;
#else
		UserInput = (IUserInput) GetComponent(typeof(IUserInput));
#endif
		isTouchInput = UserInput.IsTouchInput;
	}

    private void SetCanDie(bool isSet)
    {
        Debug.Log("Can die" + isSet);
        canDie = isSet;
    }

    /*	
	// Never called

 	private void CheckForMovement()
	{
		if(!canDie && !frog.IsDead)
		{
			SetCanDie(true);
		} 
	}

  private float DistanceFromNearestStep(Limb limb)
	{
		Vector2 limbPosition = limb.Position;
		int stepIndex = 0;
		float stepDistance;
		do
		{
		stepDistance = ((Vector2)steps[stepIndex++].position - (Vector2)limbPosition).sqrMagnitude;
		} while(stepDistance < 0);

		for(int i = stepIndex; i < steps.Count; i++)
		{
			float thisStepDistance = ((Vector2)steps[i].position - (Vector2)limbPosition).sqrMagnitude;
			if(thisStepDistance < stepDistance)
			{
				stepDistance = thisStepDistance;
				stepIndex = i;
			}
		}
		return Vector2.Distance(steps[stepIndex].position, limbPosition) / 100;
	}

	private Limb MostRecentLimb()
	{
		return (Time.time - limbs[0].lastTouch < Time.time - limbs[1].lastTouch) ? limbs[0] : limbs[1];
	}

	//Trigger Death condition if it hasn't already
	public void FirstCatch()
	{
		if(!canDie && canTouch)
		{
			canDie = true;
		}
	}

	 */

    #endregion Private Functions
}