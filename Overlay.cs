using UnityEngine;
using System.Collections;
using DG.Tweening;

public class Overlay {
    private Transform transform;
    private MeshRenderer renderer;

    public Overlay(Transform transform)
    {
        this.transform = transform;
        renderer = transform.GetComponent<MeshRenderer>();
    }

    public void Fade(bool isFadingOut = true)
    {
        Renderer renderer = this.renderer;
        DOTween.ToAlpha(() => renderer.material.GetColor("_Color"), x => renderer.material.SetColor("_Color", x), isFadingOut ? 0 : 1f, 1f);
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
        renderer.material = material;
        renderer.enabled = true;
    }
}