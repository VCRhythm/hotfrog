using UnityEngine;

public interface IController  {
    int playerID { get; set; }
    bool isPlaying { get; set; }
    Frog frog { get; set; }
    MenuManager menuManager { get; set; }
    VariableManager variableManager { get; set; }
    HUD hud { get; set; }
    bool canTouch { get; set; }

    void SetFrog(Transform frog);
    void ForceRelease(Transform step);
}