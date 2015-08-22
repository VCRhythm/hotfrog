using UnityEngine;

#if UNITY_EDITOR
using UnityEditor;
#endif

[System.Serializable]
public class SpriteLoad
{
	#if UNITY_EDITOR

	[ReadOnly]
    public string spriteName;
	public string referencePath;

	public Sprite sprite { get { return AssetDatabase.LoadAssetAtPath<Sprite>("Assets/Sprites/Frogs/" + referencePath + "/" + referencePath.Replace(" ", "") + spriteName + ".png"); } }
    public Material material;
    private bool HasSprite { get { return sprite != null;} }

	[HideInInspector]
    public SpriteRenderer renderer;
    [HideInInspector]
    public bool isHold = false;

	public SpriteLoad(string frogName, SpriteRenderer renderer)
	{
		this.renderer = renderer;
		spriteName = renderer.transform.name;
		CheckForSprite(frogName);
        material = MakeMaterial();
	}
	
	public SpriteLoad(string frogName, string variableName)
	{
        this.spriteName = variableName;

		isHold = true;
		CheckForSprite(frogName);
        material = MakeMaterial();
    }

    private Material MakeMaterial()
    {
        Material newMaterial = new Material(Shader.Find("Standard"));
        newMaterial.SetFloat("_Mode", 1.0f);
        newMaterial.EnableKeyword("_ALPHATEST_ON");
        newMaterial.EnableKeyword("_NORMALMAP");
        newMaterial.SetTexture("_BumpMap", AssetDatabase.LoadAssetAtPath<Texture>("Assets/Sprites/Frogs/" + referencePath + "/Processed/" + referencePath.Replace(" ", "") + spriteName + "_NORMALS.png"));
        //newMaterial.SetTexture("_SpecGlossMap", AssetDatabase.LoadAssetAtPath<Texture>("Assets/Sprites/Frogs/" + referencePath + "/Processed/" + referencePath.Replace(" ", "") + spriteName + "_SPECULAR.png"));
        newMaterial.SetTexture("_ParallaxMap", AssetDatabase.LoadAssetAtPath<Texture>("Assets/Sprites/Frogs/" + referencePath + "/Processed/" + referencePath.Replace(" ", "") + spriteName + "_DEPTH.png"));
        newMaterial.SetTexture("_OcclusionMap", AssetDatabase.LoadAssetAtPath<Texture>("Assets/Sprites/Frogs/" + referencePath + "/Processed/" + referencePath.Replace(" ", "") + spriteName + "_OCCLUSION.png"));
        newMaterial.SetFloat("_Glossiness", 0);
        AssetDatabase.CreateAsset(newMaterial, "Assets/Sprites/Frogs/" + referencePath + "/" + referencePath.Replace(" ", "") + spriteName + ".mat");

        return AssetDatabase.LoadAssetAtPath<Material>("Assets/Sprites/Frogs/" + referencePath + "/" + referencePath.Replace(" ", "") + spriteName + ".mat");
    }

	private void CheckForSprite(string frogName)
	{
		referencePath = frogName;

		if(!HasSprite)
		{
			if(IsUniversalSprite())
				referencePath = "Universal";
			else
				referencePath = "Hot Frog";
		}
	}

	private bool IsUniversalSprite()
	{
		return spriteName == "Tongue" || spriteName == "RightSclera" || spriteName == "LeftSclera" || spriteName == "LeftPupil" || spriteName == "RightPupil";
	}
	#endif
}