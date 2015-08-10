
uniform ivec2 presortTiles;
uniform ivec2 presortTileSize;

uniform layout(r32i) iimageBuffer sortedOrder;

#if PRESORT_SORT
void presortFrags()
{
	ivec2 tileCoord = ivec2(gl_FragCoord.xy);
	int tileIndex = tileCoord.y * presortTiles.x + tileCoord.x;
	ivec2 coord = tileCoord * presortTileSize + presortTileSize / 2;
	
	#if INDEX_WITH_TILES
	int fragIndex = tilesIndex(LFB_SIZE(lfb), ivec2(INDEX_TILE_SIZE), coord);
	#else
	int fragIndex = LFB_HASH(lfb, coord);
	#endif

	float fragDepths[MAX_FRAGS];
	
	#if 0
	ivec4 sortOp[MAX_FRAGS/4];
	#define IDX(l,i) l[i>>2][i&3]
	#else
	int sortOp[MAX_FRAGS];
	#define IDX(l,i) l[i]
	#endif

	LFB_INIT(lfb, fragIndex);
	int fragCount = 0;
	LFB_FOREACH(lfb, frag)
		fragDepths[fragCount] = LFB_FRAG_DEPTH(frag);
		IDX(sortOp,fragCount) = fragCount;
		fragCount++;
	}
	
	#if 1
	for (int j = 1; j < fragCount; ++j)
	{
		//float key = fragDepths[j>>2][j&3];
		float key = fragDepths[j];
		int opVal = IDX(sortOp,j);
		int i = j - 1;
		//while (i >= 0 && fragDepths[i>>2][i&3] > key)
		while (i >= 0 && fragDepths[i] > key)
		{
			int i1 = i + 1;
			//fragDepths[i1>>2][i1&3] = fragDepths[i>>2][i&3];
			fragDepths[i1] = fragDepths[i];
			IDX(sortOp,i1) = IDX(sortOp,i);
			--i;
		}
		int i1 = i + 1;
		//fragDepths[i1>>2][i1&3] = key;
		fragDepths[i1] = key;
		IDX(sortOp,i1) = opVal;
	}
	#endif

	for (int i = 0; i < fragCount; ++i)
	{
		int j = fragCount-i-1;
		imageStore(sortedOrder, tileIndex * MAX_FRAGS + i, ivec4(fragCount-1-IDX(sortOp,j)));
	}
	
	//fragColour = vec4(0,1,0,1);
	//fragColour.rgb = heat((fragCount)/10.0);
	//fragColour.rg = coord / vec2(800,600);
	//fragColour.rgb = vec3(fragIndex/1000000000.0);
	discard;
}
#endif

#if PRESORT_REUSE

void reuseSort(int fragIndex)
{
	ivec2 tileCoord = ivec2(gl_FragCoord.xy) / presortTileSize;
	tileCoord = min(tileCoord, presortTiles-1);
	int tileIndex = tileCoord.y * presortTiles.x + tileCoord.x;
	ivec2 centreCoord = tileCoord * presortTileSize + presortTileSize / 2;
	
	#if INDEX_WITH_TILES
	int centreIndex = tilesIndex(LFB_SIZE(lfb), ivec2(INDEX_TILE_SIZE), centreCoord);
	#else
	int centreIndex = LFB_HASH(lfb, centreCoord);
	#endif
	
	LFB_INIT(lfb, fragIndex);
	
	#if defined(LFB_COUNT) && defined(LFB_LOAD)
	float depthTest = 999.0;
	int fragCount = LFB_COUNT(lfb);
	
	if (fragCount != LFB_COUNT_AT(lfb, centreIndex))
	{
		discard;
		return;
	}
	
	fragColour = vec4(1.0);
	for (int i = 0; i < fragCount; ++i)
	{
		int offset = imageLoad(sortedOrder, tileIndex * MAX_FRAGS + i).r; //all threads in warps *should* be accessing the same tile order, so already coalesced
		LFB_FRAG_TYPE f = LFB_LOAD(lfb, offset);
		if (LFB_FRAG_DEPTH(f) > depthTest)
		{
			discard;
			return;
		}
		depthTest = LFB_FRAG_DEPTH(f);
		vec4 col = floatToRGBA8(f.x); //extract rgba from rg
		fragColour.rgb = mix(fragColour.rgb, col.rgb, col.a);
	}
	if (fragIndex == centreIndex)
		fragColour.rgb = mix(fragColour.rgb, vec3(0,1,0), 0.5);
	else
		fragColour.rgb = mix(fragColour.rgb, vec3(0,0,1), 0.5);
	//fragColour.rgb = heat((fragIndex % 123)/123.0);
	//fragColour.rgb = heat(float(fragCount)/MAX_FRAGS);
	//discard;
	#else
	discard;
	#endif
}
#endif
