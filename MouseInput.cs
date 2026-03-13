using UnityEngine;

namespace HotFrog.Input
{
    public class MouseInput : MonoBehaviour, IUserInput
    {
        public int InputCount => 2;
        public bool IsTouchInput => false;

        public Vector2 GetPosition(int touchIndex)
        {
            return UnityEngine.Input.mousePosition;
        }

        public bool HasInputStarted(int touchIndex)
        {
            return UnityEngine.Input.GetMouseButtonDown(touchIndex);
        }

        public bool IsInputOn(int touchIndex)
        {
            return UnityEngine.Input.GetMouseButton(touchIndex);
        }
    }
}
