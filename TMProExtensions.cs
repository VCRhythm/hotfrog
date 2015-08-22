using UnityEngine;
using TMPro;
using DG.Tweening;

public static class TMProExtensions {

	public static void MakeActionText(this RectTransform prefab)
	{
		RectTransform instantiated = UnityEngine.MonoBehaviour.Instantiate(prefab) as RectTransform;
		instantiated.SetParent(MenuManager.Instance.canvas, false);
		//restoreText.anchoredPosition = Vector2.zero;
		UnityEngine.MonoBehaviour.Destroy (instantiated.gameObject, 2f);
	}

	public static void Clear(this TextMeshProUGUI target)
	{
		target.text = "";
	}

	public static void Clear(this TextMeshPro target)
	{
		target.text = "";
	}

	public static void SetText(this TextMeshProUGUI target, string text)
	{
		target.SetText(text, 0);
	}

	public static Tweener DOFade (this TextMeshProUGUI target, float endValue, float duration)
	{
		return DOTween.ToAlpha (() => target.color, delegate (Color x)
		                        {
			target.color = x;
		}, endValue, duration).SetTarget (target);
	}

	public static Tweener DOFade (this TextMeshPro target, float endValue, float duration)
	{
		return DOTween.ToAlpha (() => target.color, delegate (Color x)
		                        {
			target.color = x;
		}, endValue, duration).SetTarget (target);
	}
}