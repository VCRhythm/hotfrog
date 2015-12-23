using UnityEngine;

public interface IController  {
    int ControllerID { get; set; }
    bool CanPlay { get; set; }
    bool CanTouch { get; set; }
    Frog Frog { get; set; }

    void StartLevel();
    void PlayLevel();
    void SetFrog(Frog frog);
    void ForceRelease(Transform step);
    void CollectFly();
}