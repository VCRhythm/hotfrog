using UnityEngine;
using System.Collections;

namespace HotFrog.Core
{
    public class Preload : MonoBehaviour
    {
        public static Preload Instance { get; private set; }

        [SerializeField] private Sprite[] spritesToLoad;

        private void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
        }

        IEnumerator Start()
        {
            SpriteRenderer spriteRenderer = GetComponent<SpriteRenderer>();
            for (int i = 0; i < spritesToLoad.Length; i++)
            {
                spriteRenderer.sprite = spritesToLoad[i];
                yield return null;
            }
            Destroy(gameObject);
        }
    }
}
