
#define INCLUDE_MERGESORT 0

void sortAndComposite(int fragIndex)
{
	LFB_INIT(lfb, fragIndex);
	int fragCount = 0;
	LFB_FOREACH(lfb, frag)
		if (fragCount < MAX_FRAGS)
		{
			FRAGS(fragCount) = frag;
			++fragCount;
		}
	}
	
	#if 1
	#if INCLUDE_MERGESORT
		#if MAX_FRAGS_OVERRIDE != 0
			#if MAX_FRAGS >= 64
				sort_merge(fragCount);
			#else
				sort_insert(fragCount);
			#endif
		#else
			if (fragCount > 32)
				sort_merge(fragCount);
			else
				sort_insert(fragCount);
		#endif
	#else
		sort_insert(fragCount);
		//sort_cbinsert(fragCount);
	#endif
	#endif
	
	#if DEBUG
	if (fragCount > MAX_FRAGS)
	{
		//warning: hit max frags!
		fragColour = vec4(1,0,1,1);
		return;
	}
	float lastDepth = 9999.0;
	#endif
	
	fragColour = vec4(1.0);
	for (int i = fragCount-1; i >= 0; --i)
	{
		LFB_FRAG_TYPE f = FRAGS(i);
		
		#if DEBUG
		float thisDepth = LFB_FRAG_DEPTH(FRAGS(i));
		if (thisDepth > lastDepth)
		{
			//error: out of order!
			fragColour = vec4(1,0,0,1);
			return;
		}
		lastDepth = thisDepth;
		#endif
		
		vec4 col = floatToRGBA8(f.x); //extract rgba from rg
		//col.a = 0.1;
		fragColour.rgb = mix(fragColour.rgb, col.rgb, col.a);
	}
}

void compositeOnly(int fragIndex)
{
	#if 0
	
	fragColour = vec4(1.0);
	int fragCount = 0;
	LFB_INIT(lfb, fragIndex);
	LFB_FOREACH(lfb, frag)
		if (fragCount < MAX_FRAGS)
		{
			vec4 col = floatToRGBA8(frag.x);
			fragColour.rgb = mix(fragColour.rgb, col.rgb, col.a);
			++fragCount;
		}
		else
			break;
	}
	
	#else
	
	LFB_INIT(lfb, fragIndex);
	int fragCount = 0;
	LFB_FOREACH(lfb, frag)
		if (fragCount < MAX_FRAGS)
		{
			FRAGS(fragCount) = frag;
			++fragCount;
		}
	}
	
	fragColour = vec4(1.0);
	for (int i = fragCount-1; i >= 0; --i)
	{
		LFB_FRAG_TYPE f = FRAGS(i);
		vec4 col = floatToRGBA8(f.x); //extract rgba from rg
		//col.a = 0.1;
		fragColour.rgb = mix(fragColour.rgb, col.rgb, col.a);
	}
	
	#endif
}


