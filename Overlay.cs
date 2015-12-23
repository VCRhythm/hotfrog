using UnityEngine;
using System.Collections;
using DG.Tweening;

public class Overlay {
    private Transform transform;
    private SpriteRenderer spriteRenderer;
    private MeshRenderer meshRenderer;

    public Overlay(Transform transform)
    {
        this.transform = transform;
        spriteRenderer = transform.GetComponent<SpriteRenderer>();
        meshRenderer = transform.GetComponent<MeshRenderer>();
    }

    public void Fade(bool isFadingOut = true)
    {
        if (spriteRenderer != null)
            spriteRenderer.DOFade(isFadingOut ? 0 : 1f, 1f);
        else if (meshRenderer != null)
            DOTween.ToAlpha(() => meshRenderer.material.GetColor("_Color"), x => meshRenderer.material.SetColor("_Color", x), isFadingOut ? 0 : 1f, 1f);
    }

    public IEnumerator Lower(float delay = 1f, float time = 1f)
    {
        yield return new WaitForSeconds(delay);
        transform.DOKill();
        transform.DOLocalMoveZ(10f, time);
    }

    public void Lift(float time = 1f)
    {
        transform.DOKill();
        transform.DOLocalMoveZ(0, time);
    }

    public void SetMaterial(Material material)
    {
        meshRenderer.material = material;
        meshRenderer.enabled = true;
    }

    public void SetSprite(Sprite sprite)
    {
        spriteRenderer.sprite = sprite;
        spriteRenderer.enabled = true;
    }
}