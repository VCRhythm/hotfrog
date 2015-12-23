using UnityEngine;
using DG.Tweening;

public class Speck : PooledObject {

    public enum Status
    {
        Rotating,
        Moving,
        Preparing
    }

    [ReadOnly] public Status status;
    public float rotateAngleMin = 3f;
    public float rotateAngleMax = 5f;
    [ReadOnly] public float rotateSpeed = 1f;

    private Transform targetTransform = null;
    [ReadOnly]public Vector2 nextTarget;
    [ReadOnly]public Vector2 currentTarget;
    private float targetRadius = 10f;
    private float preparationDistance = 10f;
    private bool hasTargetTransform = false;
    private Vector2 offset = Vector2.down;
    private float targetDistanceThreshold = 400f;
    private float radiusThreshold = 400f;

    void OnEnable()
    {
        rotateSpeed = Random.Range(rotateAngleMin, rotateAngleMax) * 100f;
        currentTarget = transform.position;
        offset = Vector2.down * targetRadius;
        SetTargetPosition(transform.position);
        Move(0);
    }

	void Update ()
    {
        if (status != Status.Moving)
        {
            RotateSpeck();

            if (status == Status.Preparing)
                CheckPreparationPosition();

            CheckRotationPosition();
        }

        if (status == Status.Moving && hasTargetTransform)
        {
            CheckForTargetChange();
        }
    }

    private void CheckForTargetChange()
    {
        float targetDistance = ((Vector2)targetTransform.position - new Vector2(currentTarget.x, currentTarget.y)).sqrMagnitude;

        if (targetDistance > targetDistanceThreshold)
        {
           // Debug.Log("Target Change" + targetDistance);
            SetTarget(targetTransform);
            Move(targetDistance);
        }
    }

    // If speck has rotated back to default currentTarget position, then move to nextTarget
    private void CheckPreparationPosition()
    {
        float targetDistance = ((Vector2)transform.position - new Vector2(currentTarget.x, currentTarget.y - targetRadius)).sqrMagnitude;
        if (targetDistance > preparationDistance)
        {
           // Debug.Log("Preparation Change" + targetDistance);
            offset = Vector2.down * targetRadius;
            Move(targetDistance);
        }
    }

    private void CheckRotationPosition()
    {
        float targetDistance = ((Vector2)transform.position - currentTarget).sqrMagnitude;
        if (targetDistance > radiusThreshold)
        {
            //Debug.Log("Rotation Change" + targetDistance);
            offset = Vector2.down * targetRadius;
            Move(targetDistance);
        }
    }

    private void RotateSpeck()
    {
        transform.RotateAround(hasTargetTransform && targetTransform ? (Vector2)targetTransform.position : currentTarget, transform.forward, rotateSpeed * Time.deltaTime);
    }

    private void Move(float targetDistance)
    {
        status = Status.Moving;
        currentTarget = hasTargetTransform ? (Vector2)targetTransform.position : nextTarget;

        transform.DOKill();
        transform.DOMove(currentTarget + offset, 0.5f).OnComplete(() => { status = Status.Rotating; });
    }

    public void SetTargetPosition(Vector2 position)
    {
        hasTargetTransform = false;
        status = Status.Preparing;
        nextTarget = position;
    }

    public void SetTarget(Transform target)
    {
        hasTargetTransform = true;
        status = Status.Preparing;
        targetTransform = target;
        nextTarget = targetTransform.position;
    }
}
