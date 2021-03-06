using UnityEngine;
using System.Collections;
using System.Collections.Generic;

public class FrogPackages : MonoBehaviour {

	// A singleton instance of this class
	private static FrogPackages instance;
	public static FrogPackages Instance {
		get {
			if (instance == null) instance = FindObjectOfType<FrogPackages>();
			return instance;
		}
	}

	public bool ResetPackagesOnStart = false;
	public List<Frog> frogPackages = new List<Frog>();
	public bool HasOpenPackages { get { return openPackages.Count > 1; } }
		
	[HideInInspector] public bool isViewingAllFrogs = false;
	
	private List<Vector3i> packagesSaved = new List<Vector3i>();
	private List<Vector3i> openPackages 
	{ get 
		{
			List<Vector3i> list = new List<Vector3i>();
			for(int i = 0; i < packagesSaved.Count; i++)
			{
				if(packagesSaved[i].y == 1)
					list.Add(packagesSaved[i]);
			}
			return list;
		} 
	}
	
	private int currentFrogID = -1;

	private Frog frog;

    private Controller controller;
    private VariableManager variableManager;
    private MenuManager menuManager;
    private PurchaseManager purchaseManager;

	#region Component Segments

	void Awake()
	{
        purchaseManager = GetComponentInChildren<PurchaseManager>();
        menuManager = GetComponentInChildren<MenuManager>();
        variableManager = GetComponent<VariableManager>();
        controller = transform.GetComponentInChildren<Controller>();
		
        //Clear any saved purchases
		if(ResetPackagesOnStart)
		{
			PlayerPrefs.DeleteAll();
			//PlayerPrefs.DeleteKey("FrogPackages");
		}

		LoadPackages();
	}

	#endregion Component Segments

	#region Functions

	public void MakeFrog(int id, bool hasDelay, bool canCelebrate)
	{
		if(frog != null) Destroy (frog.gameObject);

		Frog frogPrefab = null;
		for(int i = 0; i < frogPackages.Count; i++)
		{
			if(frogPackages[i].GetComponent<Frog>().id == id)
			{
				frogPrefab = frogPackages[i];
				i = frogPackages.Count;
			}
		}

		SetFrog(Instantiate (frogPrefab, new Vector3(0, -100f), Quaternion.identity) as Frog);

		currentFrogID = id;

		bool hasPackage = IsPackageOpen(id);
		float delay = hasDelay ? 2f: 0;

		StartCoroutine(menuManager.ShowFrogName(delay, frog.frogName, canCelebrate, hasPackage));

		if(!isViewingAllFrogs || hasPackage)
		{
			variableManager.currentFrogID = id;
            menuManager.ShowArrowPanelBuyButton(false);
		}
		else if(frog.canBuy == 1)
		{
            menuManager.ShowArrowPanelBuyButton(true);
        }
		else if(frog.canBuy == 0)
		{
            menuManager.ShowArrowPanelBuyButton(false);
        }

		RaiseFrog(delay);

		if(frog.audioIntroduction != null) AudioManager.Instance.PlayForAll(frog.audioIntroduction);
	}

	#region Button Callbacks

	public void PurchaseFrogFromButton()
	{
		purchaseManager.Purchase(frog);
	}

	public void NextFrog()
	{
		CycleFrog(true);
	}

	public void PrevFrog()
	{
		CycleFrog(false);
	}

	#endregion Button Callbacks
	
	public void PurchaseFrogFromStore(int id)
	{
		menuManager.DisableBuyButton(false);
		LowerAndOpenFrog(id, true);
	}

	public void RestorePurchase(int id)
	{
		BuyFrog(id, false);
	}

	public void RaiseFrog(float delay = 0)
	{
		frog.Rise(true, delay);
    }

	public void MakeSureFrogIsPurchased()
	{
		if(!IsPackageOpen(currentFrogID))
		{
			LowerAndOpenRandomFrog(false);
		}
	}

	public void LowerAndOpenFrog(int id, bool isUnlocking)
	{
		LowerFrog ();
		StartCoroutine(WaitThenOpenFrog(id, isUnlocking));
	}

	public void LowerAndOpenRandomFrog(bool isUnlocking)
	{
		LowerFrog();
		StartCoroutine(WaitThenOpenRandomFrog(isUnlocking));
	}

	public void LockPackage(int id)
	{
		for(int i = 0; i < packagesSaved.Count; i++)
		{
			if(packagesSaved[i].x == id)
			{
				if(packagesSaved[i].y == 1)
				{
					int canBuy = packagesSaved[i].z;
					packagesSaved.Remove(packagesSaved[i]);
					Debug.Log ("Package Locked: " + id);
					packagesSaved.Add(new Vector3i(id, 0, canBuy));
					SavePackages();
				}
				return;
			}
		}		
	}

	public Frog GetRandomClosedFrogForEndGamePanel()
	{
		int id = -1;
		for(int i = 0; i < packagesSaved.Count; i++)
		{
			if(packagesSaved[i].y == 0 && packagesSaved[i].z == 1)
			{
				id = packagesSaved[i].x;
				i = packagesSaved.Count;
			}
		}

		if(id < 0) return null;

		Frog randomFrog;
		for(int i = 0; i < frogPackages.Count; i++)
		{
			randomFrog = frogPackages[i].GetComponent<Frog>();
			if(randomFrog.id == id)
			{
				return randomFrog;
			}
		}
		return null;
	}

	#endregion Functions

	#region Private Functions

	private void OpenPackage(int id)
	{
		for(int i = 0; i < packagesSaved.Count; i++)
		{
			if(packagesSaved[i].x == id)
			{
				if(packagesSaved[i].y == 0)
				{
					packagesSaved.Remove(packagesSaved[i]);
					Debug.Log ("Package Opened: "+id);
					packagesSaved.Add(new Vector3i(id, 1, 1));
					SavePackages();
				}
				return;
			}
		}		
	}

	private IEnumerator WaitThenOpenFrog(int id, bool isUnlocking)
	{
		yield return new WaitForSeconds(1f);
		OpenFrog(id, false, isUnlocking);
	}

	private void OpenFrog(int id, bool hasDelay, bool isUnlocking)
	{
		MakeFrog (id, hasDelay, isUnlocking);
		if(isUnlocking) BuyFrog(id, true);
	}

	private IEnumerator WaitThenOpenRandomFrog(bool isUnlocking)
	{
		yield return new WaitForSeconds(1f);
		OpenRandomFrog(isUnlocking);
	}

	private void LowerFrog()
	{
		frog.Lower();
	}

	private static int CompareXValue(Vector3i v1, Vector3i v2)
	{
		return v1.x.CompareTo(v2.x);
	}

	private static int CompareXValueDescending(Vector3i v1, Vector3i v2)
	{
		return v2.x.CompareTo(v1.x);
	}

	private void CycleFrog(bool next)
	{
		List<Vector3i> packages = isViewingAllFrogs ? packagesSaved : openPackages;

		Vector3i choosePackage = Vector3i.zero;

		if(next)
		{
			packages.Sort(CompareXValue);
			for(int i = 0; i < packages.Count; i++)
			{
				if(packages[i].x > currentFrogID)
				{
					choosePackage = packages[i];
					i = packages.Count;
				}
			}
		}
		else
		{
			packages.Sort(CompareXValueDescending);
			for(int i=0; i < packages.Count; i++)
			{
				if(packages[i].x < currentFrogID)
				{
					choosePackage = packages[i];
					i = packages.Count;
				}
			}
		}

		if(choosePackage.x > 0)
			MakeFrog(choosePackage.x, false, false);
		else
			MakeFrog(packages[0].x, false, false);

	}

	private void LoadPackages()
	{
		Vector3i[] loadPackages = PlayerPrefsX.GetVector3iArray("FrogPackages");
		packagesSaved.Clear ();

		for(int i = 0; i < loadPackages.Length; i++)
		{
			if(loadPackages[i].x > 0)
			{
				//Debug.Log ("Loaded: " + loadPackages[i].ToString ());
				packagesSaved.Add(new Vector3i(loadPackages[i].x, loadPackages[i].y, loadPackages[i].z));
			}
		}

		for(int i = 0; i < frogPackages.Count; i++)
		{
			Frog package = frogPackages[i].GetComponent<Frog>();
			Vector3i savedPackage = packagesSaved.Find(x => x.x == package.id);

			if(savedPackage == Vector3i.zero)
			{
				//Debug.Log ("Added " + package.id + " with " + package.isUnlocked);
				packagesSaved.Add(new Vector3i(package.id, package.isUnlocked, package.canBuy));
			}
		}

		SavePackages();
	}
	
	private void SavePackages()
	{
		PlayerPrefs.DeleteKey("FrogPackages");
		PlayerPrefsX.SetVector3iArray("FrogPackages", packagesSaved.ToArray());
//		Debug.Log ("Package List");
//		for(int i = 0; i < packagesSaved.Count; i++)
//		{
//			Debug.Log ("Package " + i + ": " + packagesSaved[i].ToString());
//		}
	}

	private int RandomPackage(bool canUseAll)
	{
		if(canUseAll)
		{
			return packagesSaved[Random.Range(0, packagesSaved.Count)].x;
		}
		else
		{
			return openPackages[Random.Range(0, openPackages.Count)].x;
		}
	}
	
	private bool IsPackageOpen(int id)
	{
		for(int i = 0; i < packagesSaved.Count; i++)
		{
			if(packagesSaved[i].x == id)
			{
//				Debug.Log (packagesSaved[i]);
				if(packagesSaved[i].y == 1)
					return true;
				return false;
			}
		}
		return false;
	}
	
	private void SetFrog(Frog frog)
	{
        this.frog = frog;

        controller.SetFrog(frog);
		frog.WakeUp();
	}

	private void BuyFrog(int id, bool canSetFrog)
	{
        menuManager.ShowArrowPanelBuyButton(false);
		OpenPackage(id);

		if(canSetFrog) variableManager.currentFrogID = currentFrogID;
	}

	private void OpenRandomFrog(bool isUnlocking)
	{
		int randomFrogID;
		Vector3i randomPackage;
		do
		{
			randomFrogID = RandomPackage(isUnlocking);
			randomPackage = packagesSaved.Find (x=>x.x == randomFrogID);
		} while(randomPackage.z == 0 && randomPackage.y == 0);

		MakeFrog(randomFrogID, isUnlocking, isUnlocking);
		if(isUnlocking) BuyFrog(currentFrogID, true);
	}

//	private void PrintPackages(List<Vector2> packages)
//	{
//		for(int i=0; i< packages.Count; i++)
//		{
//			Debug.Log (packages[i]);
//		}
//	}
	
	#endregion Private Functions
}