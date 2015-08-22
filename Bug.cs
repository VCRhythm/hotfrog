using UnityEngine;
using DG.Tweening;

public class Bug : Spawn {
	
	private float moveTime = 3f;
	private float lifeSpan = 2f;
	private bool isLeaving = false;
	private bool isTame = false;

	private float halfScreenWidth = 50 * ((float)Screen.width / Screen.height);
	private float halfScreenHeight = 50;

	[HideInInspector] public Vector4 screenOffset;
	private CircleCollider2D circleCollider;

	public enum ActionType
	{
		None,
		StartGame,
	}
	public Bug.ActionType actionType;
	private System.Action grabAction;
	private System.Action disableAction;
	private System.Action decisionAfterMoving;
	private bool isGrabbed = false;
	
	void OnEnable ()
	{
		AssignInteractionAction();
		SetUpDestination();
	}
	
	void OnDisable()
	{
		CancelInvoke();
		_transform.DOKill();

		isGrabbed = false;
		isLeaving = false;
		isTame = false;
		screenOffset = new Vector4(.1f, .1f, .1f, .1f);
	}

	#region Functions
	
	public void Leave()
	{
		if(!isGrabbed)
		{
			if(!isTame) _gameObject.layer = 11;
			isLeaving = true;
			SetUpDestination();
		}
	}
	
	public override void Grab()
	{
		isGrabbed = true;
		grabAction();
	}

	public void MakeTame()
	{
		isTame = true;
		_gameObject.layer = 13;
	}

	#endregion Functions

	#region Private Functions

	private void CancelCurrentMovement()
	{
		if(DOTween.IsTweening(_transform)) 
			_transform.DOKill();
	}

	private void SetUpDestination()
	{
		Vector3 dest;
		CancelCurrentMovement();

		if(isLeaving)
		{
			if(isTame)
				dest = MenuManager.Instance.flyIconPosition;
			else
				dest = new Vector3(Random.value > .5  ? 80 : -80, 0, 1f);
		}
		else
		{
			dest = new Vector3(Random.Range(halfScreenWidth * (-1 + screenOffset.w), halfScreenWidth * (1 - screenOffset.y)),
			                   Random.Range(halfScreenHeight * (-1 + screenOffset.z), halfScreenHeight * (1 - screenOffset.x)), 1f );
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
		_transform.DOMove (dest, moveTime).SetEase(Ease.OutBack);
	}

	protected override void OnTriggerEnter2D (Collider2D other)
	{
		if(isTame)
		{
			grabAction();
			MenuManager.Instance.UpdateFlyToGoText();
			AudioManager.Instance.Play(AudioManager.Instance.flySound);
		}

		base.OnTriggerEnter2D (other);
	}

	private void AssignInteractionAction()
	{
		grabAction = () => { CancelCurrentMovement(); };

		switch(actionType)
		{
		case Bug.ActionType.StartGame:
			grabAction += () => { TouchManager.Instance.frog.tongue.AddToCatchActions( () => { MenuManager.Instance.StartGame(); Destroy(_gameObject);} ); };
			decisionAfterMoving = () => { Invoke ("SetUpDestination", lifeSpan); };
			break;
		case Bug.ActionType.None:
			grabAction += () => { HUD.Instance.BugsCaught++; };
			decisionAfterMoving = () => { Invoke("Leave", lifeSpan); };
			break;
		}
	}

	#endregion Private Functions
}