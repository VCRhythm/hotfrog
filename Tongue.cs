using UnityEngine;

public class Tongue : MonoBehaviour {

	private Transform target;
	private Vector3 startScale;
	private bool isExpanding = false;
	private float expandSpeed = .05f;
	private float retractSpeed = .03f;
	private float startTime;
	private float journeyLength;
	private Transform _transform;
	private float spriteY;
	
	private System.Action catchAction;

	void Awake()
	{
		ResetCatchAction();
		_transform = transform;
		startScale = _transform.localScale;
		spriteY = GetComponent<SpriteRenderer>().sprite.bounds.size.y;
	}

	void FixedUpdate()
	{
		if(isExpanding && target != null)
		{
			if(journeyLength > _transform.localScale.y * spriteY)
			{
				_transform.up = new Vector2(target.position.x, target.position.y) - (Vector2)_transform.position;
				_transform.localScale = new Vector3(startScale.x, _transform.localScale.y + expandSpeed, startScale.z);
			}
			else
			{
				catchAction();
				ResetCatchAction();
				
				isExpanding = false;
			}
		}
		else if(_transform.localScale.y > 0)
		{
			isExpanding = false;
			_transform.localScale = new Vector3(startScale.x, Mathf.Max(_transform.localScale.y - retractSpeed, 0), startScale.z);
		}
	}

	#region Functions

	public void Expand(Transform endTarget)
	{
		if( isExpanding) return;

		AudioManager.Instance.Play(AudioManager.Instance.slurpSound);

		target = endTarget;
		journeyLength = Vector2.Distance(target.position, _transform.position);
		isExpanding = true;
	}
	
	public void AddToCatchActions(System.Action newCatchAction)
	{
		catchAction += newCatchAction;
	}

	#endregion Functions

	#region Private Functions

	private void DefaultCatchAction()
	{
		target.SpawnScript().Destroy();
		AudioManager.Instance.Play(AudioManager.Instance.squishSound);
	}

	private void ResetCatchAction()
	{
		catchAction = () => { DefaultCatchAction(); };
	}

	#endregion Private Functions
}