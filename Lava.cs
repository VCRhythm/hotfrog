using UnityEngine;
using DG.Tweening;
using HotFrog.Audio;
using HotFrog.Spawning;

namespace HotFrog.Entities
{
public class Lava : MonoBehaviour {

	private ObjectPool splashPool;
	private MeshRenderer _renderer;
	Renderer skyRenderer;
	Transform heatPlane;
	Material heatMaterial;
    bool heatIsLowered = false;

	[SerializeField] private Transform background;

	void Awake ()
	{
		splashPool = GetComponent<ObjectPool>();
		_renderer = transform.GetChild(0).GetComponent<MeshRenderer>();

		skyRenderer = background.Find("Sky").GetComponent<Renderer>();
		heatPlane = background.Find("Heat");
		heatMaterial = heatPlane.GetComponent<MeshRenderer>().material;
	}

	#region Public Functions

	public void FallSplash()
	{
		AudioManager.Instance.PlayForAll(AudioManager.Instance.hurtSound);

        DOTween.To(UpdateGradient, 1, 0.2f, .5f).SetDelay(3f);
	}

	public void Splash(Vector2 splashPosition, int splashCount)
	{
		for(int i=0; i< splashCount; i++)
			splashPool.GetTransformAndSetPosition(splashPosition);
	}

	public void Reset()
	{
		heatMaterial.SetFloat("Offset", .3f);
		DOTween.To (UpdateGradient, _renderer.material.GetFloat("_UVYOffset"), 1f, 1f);
	}

	public void LiftHeat(bool isHot)
	{
        if (heatIsLowered)
        {
            heatPlane.DOLocalMoveZ(0, 2f).SetEase(Ease.OutExpo);

            if (isHot)
            {
                heatMaterial.SetFloat("Offset", 0);
            }
            heatIsLowered = false;
        }
	}

	public void LowerHeat()
	{
        if (!heatIsLowered)
        {
            Debug.Log("Lower Heat");
            heatPlane.DOLocalMoveZ(10f, 2f).OnComplete(() => { Debug.Log("Heat Lowered"); });
            heatIsLowered = true;
        }
	}

	#endregion Public Functions

	private void UpdateGradient(float value)
	{
		_renderer.material.SetFloat("_UVYOffset", value);
	}

	private void FadeBackgroundToColor(Color newColor)
	{
		skyRenderer.sharedMaterial.DOColor(newColor, 5f);
	}
}
}
