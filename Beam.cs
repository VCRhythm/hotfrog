using UnityEngine;
using System.Collections;

public class Beam : MonoBehaviour {

	private Transform baseTransform;
	private Transform targetTransform;
	private Vector3 startScale;
	private bool isExpanding = false;
	private float expandSpeed = .6f;
	private float startTime;
	private float journeyLength;
	private Transform _transform;
	private float spriteY;
	private SpriteRenderer _renderer;

	void Awake()
	{
		_transform = transform;
		startScale = _transform.localScale;
		_renderer = GetComponent<SpriteRenderer>();
		spriteY = _renderer.sprite.bounds.size.y;
	}

	void FixedUpdate()
	{
		if(targetTransform != null)
		{
			journeyLength = Vector2.Distance(targetTransform.position, _transform.position);
			_transform.up = new Vector2(targetTransform.position.x, targetTransform.position.y) - (Vector2)_transform.position;

			if(baseTransform != null) _transform.position = baseTransform.position;

			if(isExpanding && journeyLength > _transform.localScale.y * spriteY)
			{
				_transform.localScale = new Vector3(startScale.x, _transform.localScale.y + expandSpeed, startScale.z);
			}
			else
			{
				isExpanding = false;
				StartCoroutine(KeepTransformScaleCorrect());
			}
		}
	}

	public void Expand(Transform from, Transform to, Color color)
	{
		AudioManager.Instance.Play(AudioManager.Instance.slurpSound);
		_renderer.color = color;
		baseTransform = from;
		targetTransform = to;

		isExpanding = true;
	}

	private IEnumerator KeepTransformScaleCorrect()
	{
		while(true)
		{
			_transform.localScale = new Vector3(startScale.x, journeyLength / spriteY, startScale.z);

			yield return new WaitForSeconds(1f);
		}

	}
}