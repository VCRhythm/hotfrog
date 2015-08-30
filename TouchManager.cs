using UnityEngine;

public class TouchManager : Controller {

    #region Fields

    public override int playerID { get; set; }
	
    //Input
    private bool canTouch = false;
    public override bool CanTouch { get { return canTouch; } set { canTouch = value;  } }
	TouchIndicator[] touchIndicators = new TouchIndicator[2];

    public override bool isPlaying { get; set; }

    //Guidance
    public TouchIndicator touchIndicatorPrefab;
    public Transform[] guidancePrefabs = new Transform[2];

    //Components
    public VariableManager variableManager { get; set; }
    public MenuManager menuManager { get; set; }
    public HUD hud { get; set; }
    CanvasGroup endGameCanvas;
    ObjectPool qualityText;
        
    #endregion Fields

    #region Component Segments

    void Awake()
	{
        variableManager = GetComponentInParent<VariableManager>();
        menuManager = transform.parent.GetComponentInChildren<MenuManager>();
        hud = menuManager.GetComponentInChildren<HUD>();

		SetUpTouchIndicators();

		qualityText = GetComponent<ObjectPool>();
    }
	
	void Update ()
	{
        if (CanTouch)
        {
            MoveLimbs();

            if (Input.GetKeyDown(KeyCode.Z))
            {
                Application.CaptureScreenshot("hfScreenShot"+Time.time+".png", 4);
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
                    {
                        DecrementOtherTouchIndices(i);
                    }
                }
            }

            FreeTouches();
                
			if(!HasStep && !frog.isDead && frog.canDie )
			{
                if(LevelManager.Instance.ReportFall(this))
                {
                    frog.canDie = false;
                    EndLevel();
                }
			}
		}

	}
	
	#endregion Component Segments

	#region Functions
	
	public override void PlayLevel()
	{
        ResetStats();
        frog.Play();
        isPlaying = true;
	}
	
    public override void CollectFly()
    {
        hud.BugsCaught++;
        menuManager.UpdateFlyToGoText();
    }

    public override void StartLevel()
    {
        menuManager.StartGame();
    }

    public override void AddToTongueCatchActions(System.Action action)
    {
        frog.tongue.AddToCatchActions(action);
    }

    #endregion Functions

    #region Private Functions

    private void EndLevel(bool hasDied = true)
    {
        isPlaying = false;
        CanTouch = false;

        HideTouchIndicators();

        variableManager.SaveStats(hud.BugsCaught, hud.StepsClimbed);
        menuManager.SetGrabStats(grabStats);
        if (hasDied)
        {
            menuManager.ShowEndGamePanel();
        }
        frog.EndGame(hasDied);
        Invoke("ResumeTouch", hasDied ? 1f : 0);
    }

    private void ResumeTouch()
    {
        CanTouch = true;
    }

    private void Register()
    {
        playerID = ControllerManager.playerCount++;
        ControllerManager.Instance.Register(this);
    }

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
			
	private void SetUpBarriers()
	{
		float halfScreenWidth = 50 * ((float)Screen.width / Screen.height);

		GameObject.Find("LeftRockBarrier").transform.position = new Vector2(-halfScreenWidth-1, -1.8f);
		GameObject.Find("RightRockBarrier").transform.position = new Vector2(halfScreenWidth+1, -1.8f);
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

    protected override void TouchStep(Transform step, int touchIndex, Vector2 worldPos)
    {
        if (isPlaying && !step.StepSpawnScript().wasGrabbed)
        {
            float distance = (worldPos - (Vector2)step.position).sqrMagnitude;
            int index = distance > 20 ? 0 : (distance > 10 ? 1 : 2);
            TrackGrabQuality(index, worldPos);
            hud.StepsClimbed++;
        }

        Limb limb = GetFreeLimb();
        limb.SetStep(step, touchIndex);

        LevelManager.Instance.CheckForStepTrigger(step, hud.StepsClimbed);
    }


    protected override void TrackGrabQuality(int index, Vector2 worldPos)
	{
        qualityText.GetTransformAndSetPosition(worldPos, index);

        if (index == 0)
		{
			AudioManager.Instance.PlayForAll(AudioManager.Instance.okVoiceSound);
			grabStats.x++;
		}
		else if(index == 1)
		{
			AudioManager.Instance.PlayForAll(AudioManager.Instance.greatVoiceSound);
			grabStats.y++;
		}
		else if(index == 2)
		{
			AudioManager.Instance.PlayForAll(AudioManager.Instance.perfectVoiceSound);
			grabStats.z++;
		}
	}

	private void ResetStats()
	{
		hud.SetInitialStats();
		grabStats = Vector4i.zero;
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
