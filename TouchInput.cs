using UnityEngine;

namespace HotFrog.Input
{
    public class TouchInput : MonoBehaviour, IUserInput
    {
        public int InputCount => UnityEngine.Input.touchCount;
        public bool IsTouchInput => true;

        public Vector2 GetPosition(int touchIndex)
        {
            return UnityEngine.Input.GetTouch(touchIndex).position;
        }

        public bool HasInputStarted(int touchIndex)
        {
            return UnityEngine.Input.GetTouch(touchIndex).phase == TouchPhase.Began;
        }

        public bool IsInputOn(int touchIndex)
        {
            TouchPhase phase = UnityEngine.Input.GetTouch(touchIndex).phase;
            return phase == TouchPhase.Began || phase == TouchPhase.Moved || phase == TouchPhase.Stationary;
        }
    }
}
