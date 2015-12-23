using UnityEngine;

public class StepAndScenery : Spawn
{
    private Animator animator;
    private Step step;

    protected override void Awake()
    {
        base.Awake();
        animator = GetComponent<Animator>();
        step = GetComponentInChildren<Step>();
    }

    public override void Destroy(float fadeDelay, float fadeTime, float destroyDelay)
    {
        if (animator)
        {
            animator.SetTrigger("Exit");
        }
        step.canPull = false;

        base.Destroy(fadeDelay, fadeTime, destroyDelay);
    }

    public override void Destroy()
    {
        step.Destroy();
        base.Destroy();
    }
}
