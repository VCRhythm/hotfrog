using UnityEngine;

[RequireComponent(typeof(Rigidbody2D))]
public class RigidbodySpawn : Spawn, IGrabable
{
    public bool hasMaxY = false;
    public float maxY = 0;
    public float speedModifierMin = 1f;
    public float speedModifierMax = 1f;
    protected float speedModifier = 1f;

    protected Rigidbody2D rb2D;
    private Vector2 currentSpeed = Vector2.zero;
    protected bool hasRotationFrozen = false;
    private float savedRotationForce;

    protected override void Awake()
    {
        base.Awake();

        rb2D = GetComponent<Rigidbody2D>();

        hasRotationFrozen = rb2D.freezeRotation;
    }

    protected virtual void OnEnable()
    {
        speedModifier = Random.Range(speedModifierMin, speedModifierMax);
    }

    protected virtual void FixedUpdate()
    {
        if (hasMaxY && rb2D.position.y >= maxY && rb2D.velocity.y > 0)
        {
            rb2D.velocity = Vector2.zero;
            rb2D.angularVelocity = 0;
            SpawnManager.Instance.HaltPulling();
            currentSpeed = Vector2.zero;
        }
        else if (speed != Vector2.zero)
        {
            if (speed != currentSpeed)
            {
                Debug.Log(currentSpeed.y + " and " + speed.y);
                rb2D.velocity = new Vector2(Mathf.Sign(currentSpeed.x) != Mathf.Sign(speed.x) ? 0 : rb2D.velocity.x, Mathf.Sign(currentSpeed.y) != Mathf.Sign(speed.y) ? 0 : rb2D.velocity.y);
                
                //rb2D.angularVelocity = 0;

                currentSpeed = speed;
            }

            rb2D.AddForce(speed * speedModifier * Time.deltaTime, ForceMode2D.Impulse);
        }
    }
}