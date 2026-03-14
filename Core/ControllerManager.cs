using UnityEngine;
using System;
using System.Collections.Generic;
using HotFrog.Player;

namespace HotFrog.Core
{
    public class ControllerManager : MonoBehaviour
    {
        public static ControllerManager Instance { get; private set; }

        public static int playerCount = 0;

        public bool anyPlaying => controllers.Exists(c => c.IsPlaying);

        public bool allCanPlay => controllers.TrueForAll(c => c.CanPlay);

        private List<Controller> controllers = new List<Controller>();

        private void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
        }

        public void Register(Controller controller)
        {
            controllers.Add(controller);
        }

        public void Deregister(Controller controller)
        {
            controllers.Remove(controller);
        }

        public void TellControllers(Action<Controller> action)
        {
            for (int i = 0; i < controllers.Count; i++)
            {
                action(controllers[i]);
            }
        }

        public void TellController(int playerID, Action<Controller> action)
        {
            Controller controller = controllers.Find(x => x.ControllerID == playerID);
            action(controller);
        }

        public void TellController(Controller controller, Action<Controller> action)
        {
            action(controller);
        }
    }
}
