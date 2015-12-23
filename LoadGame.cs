using UnityEngine;
using System.Collections;
using UnityEngine.SceneManagement;

public class LoadGame : MonoBehaviour {

	private WaitForSeconds wait = new WaitForSeconds(0.1f);

	IEnumerator Start () 
	{
        yield return SceneManager.LoadSceneAsync(1);

        while (Preload.Instance != null)
        {
            yield return wait;
        }

		GetComponent<Animator>().SetTrigger("FadeAway");
	}

	private void Destroy()
	{
		Destroy(gameObject);
	}
}
