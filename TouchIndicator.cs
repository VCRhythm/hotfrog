using UnityEngine;
using DG.Tweening;

public class TouchIndicator : MonoBehaviour {

	[ReadOnly]public int touchIndex = -1;
	public bool IsUnused { get { return touchIndex == -1; } }
	private Color color = Color.white;
	private SpriteRenderer spriteRenderer;
	private Transform _transform;

	void Awake()
	{
		spriteRenderer = GetComponent<SpriteRenderer>();
		_transform = transform;
	}
	
	public void Show(int newIndex, Sprite sprite)
	{
		touchIndex = newIndex;
		spriteRenderer.sprite = sprite;
		spriteRenderer.color = new Color(1, 1, 1, 1);
	}

	public void SetPosition(Vector2 position)
	{
		_transform.position = position;
	}

	public void Hide()
	{
		touchIndex = -1;
		CancelTween();
		//color = Color.white;
		spriteRenderer.DOFade(0, .5f);
	}


	#region Private Functions

	private void SetColorByDistance(Vector2 position, bool isNewIndicator = false)
	{
		float distance = (position - Vector2.zero).sqrMagnitude;
		if(distance > 200f)
			SetColor (Color.red, !isNewIndicator);
		else if(distance > 100f)
			SetColor(Color.yellow, !isNewIndicator);
		else
			SetColor(Color.green, false);
	}
	
	private void SetColorByTime(float timeElapsed, bool isNewIndicator = false)
	{
		if(timeElapsed >= 2f)
			SetColor(Color.red, !isNewIndicator);
		else if(timeElapsed >= 1f && color != Color.red)
			SetColor(Color.yellow, !isNewIndicator);
		else if(color != Color.red && color != Color.yellow)
			SetColor(Color.green, false);
	}

	private void SetColorByY(float yVal, bool isNewIndicator = false)
	{
		if(yVal > 10)
			SetColor(Color.green, false);
		else if(yVal > -10)
			SetColor (Color.yellow, !isNewIndicator);
		else
			SetColor(Color.red, !isNewIndicator);
	}
	
	private void SetColor(Color newColor, bool isAnimating = true)
	{
		if(color == newColor) return;
		color = newColor;

		CancelTween();
		spriteRenderer.DOColor(color, isAnimating ? 1f : 0);
	}

	private void CancelTween()
	{
		spriteRenderer.DOKill();
	}
	
	#endregion Private Functions

}