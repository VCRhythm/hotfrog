using System;
using UnityEngine;

[System.Serializable]
public struct Vector4i
{
	public static readonly Vector4i zero = new Vector4i(0, 0, 0, 0);
	public static readonly Vector4i one = new Vector4i(1, 1, 1, 1);
	
	public static readonly Vector4i forward = new Vector4i(0, 0, 1);
	public static readonly Vector4i back = new Vector4i(0, 0, -1);
	public static readonly Vector4i up = new Vector4i(0, 1, 0);
	public static readonly Vector4i down = new Vector4i(0, -1, 0);
	public static readonly Vector4i left = new Vector4i(-1, 0, 0);
	public static readonly Vector4i right = new Vector4i(1, 0, 0);
	public static readonly Vector4i regress = new Vector4i(0, 0, 0, -1);
	public static readonly Vector4i progress = new Vector4i(0, 0, 0, 1);
	
	public static readonly Vector4i[] directions = new Vector4i[] {
		left, right,
		back, forward,
		down, up,
		regress, progress
	};
	
	public int x, y, z, w;
	
	public Vector4i(int x, int y, int z, int w)
	{
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}
	
	public Vector4i(int x, int y)
	{
		this.x = x;
		this.y = y;
		this.z = 0;
		this.w = 0;
	}

	public Vector4i(int x, int y, int z)
	{
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = 0;
	}
	
	public Vector4i(Vector4 original, System.Func<float, int> convert)
	{
		this.x = convert(original.x);
		this.y = convert(original.y);
		this.z = convert(original.z);
		this.w = convert(original.w);
	}
	
	public static Vector4i operator -(Vector4i a)
	{
		return new Vector4i(-a.x, -a.y, -a.z, -a.w);
	}
	
	public static Vector4i operator -(Vector4i a, Vector4i b)
	{
		return new Vector4i(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w);
	}
	
	public static Vector4i operator +(Vector4i a, Vector4i b)
	{
		return new Vector4i(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w);
	}
	
	public static Vector4i operator *(Vector4i v, int factor)
	{
		return new Vector4i(v.x * factor, v.y * factor, v.z * factor, v.w * factor);
	}
	
	public static Vector4 operator *(Vector4i v, float factor)
	{
		return new Vector4(v.x * factor, v.y * factor, v.z * factor, v.w * factor);
	}
	
	public static Vector4i operator /(Vector4i v, int factor)
	{
		return new Vector4i(v.x / factor, v.y / factor, v.z / factor, v.w / factor);
	}
	
	public static implicit operator Vector4(Vector4i v)
	{
		return new Vector4(v.x, v.y, v.z, v.w);
	}
	
	public static bool operator ==(Vector4i a, Vector4i b)
	{
		return a.x == b.x &&
			a.y == b.y &&
				a.z == b.z &&
				a.w == b.w;
	}
	
	public static bool operator !=(Vector4i a, Vector4i b)
	{
		return a.x != b.x ||
			a.y != b.y ||
				a.z != b.z ||
				a.w != b.w;
	}
	
	public static Vector4i Min(Vector4i a, Vector4i b)
	{
		return new Vector4i(Mathf.Min(a.x, b.x), Mathf.Min(a.y, b.y), Mathf.Min(a.z, b.z), Mathf.Min (a.w, b.w));
	}
	
	public static Vector4i Max(Vector4i a, Vector4i b)
	{
		return new Vector4i(Mathf.Max(a.x, b.x), Mathf.Max(a.y, b.y), Mathf.Max(a.z, b.z), Mathf.Max (a.w, b.w));
	}
	
	public static Vector4i Floor(Vector4 v)
	{
		return new Vector4i(
			Mathf.FloorToInt(v.x),
			Mathf.FloorToInt(v.y),
			Mathf.FloorToInt(v.z),
			Mathf.FloorToInt(v.w)
			);
	}
	
	public static Vector4i Ceil(Vector4 v)
	{
		return new Vector4i(
			Mathf.CeilToInt(v.x),
			Mathf.CeilToInt(v.y),
			Mathf.CeilToInt(v.z),
			Mathf.CeilToInt(v.w)
			);
	}
	
	public static Vector4i Round(Vector4 v)
	{
		return new Vector4i(
			Mathf.RoundToInt(v.x),
			Mathf.RoundToInt(v.y),
			Mathf.RoundToInt(v.z),
			Mathf.RoundToInt(v.w)
			);
	}
	
	public Vector4i Mul(Vector4i factor)
	{
		return new Vector4i(x * factor.x, y * factor.y, z * factor.z, w * factor.w);
	}
	
	public Vector4i Div(Vector4i factor)
	{
		return new Vector4i(x / factor.x, y / factor.y, z / factor.z, w / factor.w);
	}
	
	public bool Any(Predicate<int> p)
	{
		if (p(x))
			return true;
		if (p(y))
			return true;
		if (p(z))
			return true;
		if (p(w))
			return true;
		
		return false;
	}
	
	public override bool Equals(object other)
	{
		if (!(other is Vector4i)) return false;
		Vector4i vector = (Vector4i)other;
		return x == vector.x &&
			y == vector.y &&
				z == vector.z &&
				w == vector.w;
	}
	
	public override int GetHashCode()
	{
		return x.GetHashCode() ^ y.GetHashCode() << 2 ^ z.GetHashCode() >> 2 ^ w.GetHashCode() >> 1;
	}
	
	public override string ToString()
	{
		return string.Format("Vector4i({0} {1} {2} {3})", x, y, z, w);
	}
}
