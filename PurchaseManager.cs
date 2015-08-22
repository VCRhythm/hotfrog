using UnityEngine;
using System.Collections.Generic;
using Soomla.Store;
using Soomla.Highway;
using System.Text.RegularExpressions;

public class PurchaseManager : MonoBehaviour {

	// A singleton instance of this class
	private static PurchaseManager instance;
	public static PurchaseManager Instance {
		get {
			if (instance == null) instance = GameObject.FindObjectOfType<PurchaseManager>();
			return instance;
		}
	}

	public RectTransform restoredTextPrefab;
	public bool isUsingHighway = true;
	public bool isUsingStore = true;
	private bool hasStarted = false;
	private StoreAssets assets;

	void Start()
	{
		if(isUsingStore)
		{
		assets = new StoreAssets();
#if !UNITY_EDITOR
		if(isUsingHighway) SoomlaHighway.Initialize();
#endif
		SoomlaStore.Initialize(assets);

		StoreEvents.OnCurrencyBalanceChanged += OnCurrencyBalanceChanged;
		StoreEvents.OnMarketPurchase += OnMarketPurchase;
		//StoreEvents.OnGoodBalanceChanged += OnGoodBalanceChanged;
		StoreEvents.OnMarketRefund += OnMarketRefund;
		StoreEvents.OnUnexpectedErrorInStore += OnUnexpectedErrorInStore;
		StoreEvents.OnRestoreTransactionsFinished += OnRestoreTransactionsFinished;

		if(FrogPackages.Instance.ResetPackagesOnStart)
			ClearPurchases();
		}
	}

	public void StartService()
	{
		if(!hasStarted)
		{
			hasStarted = true;
			SoomlaStore.StartIabServiceInBg();
		}
	}

	public void StopService()
	{
		if(hasStarted)
		{
			SoomlaStore.StartIabServiceInBg();
			hasStarted = false;
		}
	}

	public void Purchase(Frog frog)
	{
		string productID = frog.frogName.Replace(" ", "_").ToLower();
		SoomlaStore.BuyMarketItem(productID, "Purchase Complete");
	}

	public void OnCurrencyBalanceChanged(VirtualCurrency virtualCurrency, int balance, int amountAdded)
	{
		if(amountAdded > 0)
			MenuManager.Instance.SpawnGiftFlys(false, amountAdded);
		else
			HUD.Instance.ChangeBugCount(amountAdded);
	}

	public void ClearPurchases()
	{
		VirtualGood[] virtualGoods = assets.GetGoods();
		foreach(VirtualGood good in virtualGoods)
		{
			good.ResetBalance(0);
			FrogPackages.Instance.LockPackage(GetID(good.ItemId));
		}
	}

//	public void OnGoodBalanceChanged(VirtualGood good, int balance, int amountAdded)
//	{
//		Debug.Log ("Balance changed");
//		int id = GetID(good.ItemId);
//		if(id > 0 && balance > 0)
//			FrogPackages.Instance.RestorePurchase(id);
		//else if(id > 0 && balance < 1)
		//	FrogPackages.Instance.LockPackage(id);
//	}

	public void OnMarketPurchase(PurchasableVirtualItem pvi, string payload, Dictionary<string, string> extra)
	{
		int id = GetID(pvi.ItemId);
		if(id > 0 && pvi.GetBalance() > 0)
			FrogPackages.Instance.PurchaseFrogFromStore(id);
	}
	
	public void OnMarketRefund(PurchasableVirtualItem pvi)
	{
		int id = GetID(pvi.ItemId);

		if(id > 0)
			FrogPackages.Instance.LockPackage(id);
	}

	public void OnUnexpectedErrorInStore(string message)
	{
		MenuManager.Instance.DisableBuyButton(true);
	}

	public void OnRestoreTransactionsFinished(bool success)
	{
		if(success)
		{
			VirtualGood[] virtualGoods = assets.GetGoods();
			foreach(VirtualGood good in virtualGoods)
			{
				int id = GetID (good.ItemId);
				if(id > 0 && good.GetBalance() > 0)
				{
					Debug.Log ("Restoring: " + id);
					FrogPackages.Instance.RestorePurchase(id);
				}
				else
					FrogPackages.Instance.LockPackage(id);
			}
		}
	}

	private int GetID(string stringID)
	{
		int id;
		int.TryParse(Regex.Split(stringID, "_")[0], out id);
		if(id > 0 && id < 999)
			return id;
		else
			return -1;
	}
}