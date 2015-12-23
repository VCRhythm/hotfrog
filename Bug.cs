using UnityEngine;
using DG.Tweening;

public class Bug : Spawn {
	
	private float moveTime = 3f;
	private float lifeSpan = 2f;
	private bool isLeaving = false;
	private int ownerID = -1;

	private float halfScreenWidth = 50 * ((float)Screen.width / Screen.height);
	private float halfScreenHeight = 50;

	[HideInInspector] public Vector4 screenOffset;
	private CircleCollider2D circleCollider;

	public enum ActionType
	{
		None,
		StartGame,
	}
	public ActionType actionType;
	private System.Action<int> grabAction;
	private System.Action disableAction;
	private System.Action decisionAfterMoving;
	private bool isGrabbed = false;

    void OnEnable()
	{
		AssignInteractionAction();
		SetUpDestination();
	}
	
	void OnDisable()
	{
		CancelInvoke();
		transform.DOKill();

		isGrabbed = false;
		isLeaving = false;
		ownerID = -1;
		screenOffset = new Vector4(.1f, .1f, .1f, .1f);
	}

	#region Functions
	
	public void Leave()
	{
		if(!isGrabbed)
		{
			if(ownerID < 0) gameObject.layer = 11;
			isLeaving = true;
			SetUpDestination();
		}
	}
	
	public override void Grab(int playerID)
	{
		isGrabbed = true;
		grabAction(playerID);
	}

	public void MakeTame(int playerID)
	{
        ownerID = playerID;
		gameObject.layer = 13;
	}

	#endregion Functions

	#region Private Functions

	private void CancelCurrentMovement()
	{
		if(DOTween.IsTweening(transform)) 
			transform.DOKill();
	}

	private void SetUpDestination()
	{
		Vector3 dest;
		CancelCurrentMovement();

		if(isLeaving)
		{
            if (ownerID >= 0)
            {
                //Fly to top right corner
                dest = new Vector3(halfScreenWidth * 2, 50, -1f);
            }
            else
            {
                dest = new Vector3(Random.value > .5 ? 80 : -80, 0, -1f);
            }
		}
		else
		{
			dest = new Vector3(Random.Range(halfScreenWidth * (-1 + screenOffset.w), halfScreenWidth * (1 - screenOffset.y)),
			                   Random.Range(halfScreenHeight * (-1 + screenOffset.z), halfScreenHeight * (1 - screenOffset.x)), -1f );
/*			Debug.Log (string.Format ("Dest: {4}, Left: {0}, Right: {1}, Top: {2}, Bottom: {3}", 
			                          halfScreenWidth * (-1 + offset.w), 
			                          halfScreenWidth * (1 - offset.y),
			                          halfScreenHeight * (1 - offset.x),
			                          halfScreenHeight * (-1 + offset.z),
			                          dest
			                          )); */
		}

		MoveTo(dest);
		decisionAfterMoving();
	}

	private void MoveTo(Vector3 dest)
	{
		transform.DOMove (dest, moveTime).SetEase(Ease.OutBack);
	}

	protected override void OnTriggerEnter2D (Collider2D other)
	{
		if(ownerID >= 0)
		{
			grabAction(ownerID);
			AudioManager.Instance.PlayForAll(AudioManager.Instance.flySound);
		}

		base.OnTriggerEnter2D (other);
	}

	private void AssignInteractionAction()
	{
		grabAction = (int playerID) => { CancelCurrentMovement(); };

		switch(actionType)
		{
            case ActionType.StartGame:
                
			    grabAction += (int playerID) => 
                {
                    ControllerManager.Instance.TellController(playerID, (x) =>
                    {
                        x.frog.tongue.AddToCatchActions(() =>
                            {
                                x.AteStartBug();
                                Destroy();
                            });
                    });
                };
			    decisionAfterMoving = () => { Invoke ("SetUpDestination", lifeSpan); };
			    break;

            case ActionType.None:
                grabAction += (int playerID) => 
                {
                    ControllerManager.Instance.TellController(playerID, (x) =>
                    {
                        x.CollectFly();
                    });
                };
			    decisionAfterMoving = () => { Invoke("Leave", lifeSpan); };
			    break;
		}
	}

	#endregion Private Functions
}