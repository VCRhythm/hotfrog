using UnityEngine;
using System.Collections;

public class LoadGame : MonoBehaviour {

	private WaitForSeconds wait = new WaitForSeconds(0.1f);

	IEnumerator Start () 
	{
		Application.LoadLevelAdditive(1);

		while(Application.isLoadingLevel)
			yield return wait;

		while(Preload.Instance != null)
			yield return wait;

		GetComponent<Animator>().SetTrigger("FadeAway");
		MenuManager.Instance.InitialSetup();
	}

	private void Destroy()
	{
		Destroy(gameObject);
	}
}
