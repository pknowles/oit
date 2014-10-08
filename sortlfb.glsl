
LFB_FRAG_TYPE leftArray[MAX_FRAGS/2];
void merge(int step, int a, int b, int c)
{
	int i;
	for (i = 0; i < step; ++i)
		leftArray[i] = FRAGS(a+i);

	i = 0;
	int j = 0;
	for (int k = a; k < c; ++k)
	{
		if (b+j >= c || (i < step && LFB_FRAG_DEPTH(leftArray[i]) < LFB_FRAG_DEPTH(FRAGS(b+j))))
			FRAGS(k) = leftArray[i++];
		else
			FRAGS(k) = FRAGS(b+j++);
	}
}

void sort_merge(int fragCount)
{
	int n = fragCount;
	int step = 1;
	while (step <= n)
	{
		int i = 0;
		while (i < n - step)
		{
			merge(step, i, i + step, min(i + step + step, n));
			i += 2 * step;
		}
		step *= 2;
	}
}

void sort_shell(int fragCount)
{
	int inc = fragCount / 2;
	while (inc > 0)
	{
		for (int i = inc; i < fragCount; ++i)
		{
			LFB_FRAG_TYPE tmp = FRAGS(i);
			int j = i;
			while (j >= inc && LFB_FRAG_DEPTH(FRAGS(j - inc)) > LFB_FRAG_DEPTH(tmp))
			{
				FRAGS(j) = FRAGS(j - inc);
				j -= inc;
			}
			FRAGS(j) = tmp;
		}
		inc = int(inc / 2.2 + 0.5);
	}
}

void sort_insert(int fragCount)
{
	for (int j = 1; j < fragCount; ++j)
	{
		LFB_FRAG_TYPE key = FRAGS(j);
		int i = j - 1;
		while (i >= 0 && LFB_FRAG_DEPTH(FRAGS(i)) > LFB_FRAG_DEPTH(key))
		{
			FRAGS(i+1) = FRAGS(i);
			--i;
		}
		FRAGS(i+1) = key;
	}
}

void sort_cbinsert(int fragCount)
{
	int c = MAX_FRAGS;
	
	//NOTE: requires MAX_FRAGS be a power of 2!!!!! use mod (%) otherwise
	#define CFRAG(i) FRAGS((c+(i))&(MAX_FRAGS-1))
	
	LFB_FRAG_TYPE tmp;
	int left, right, m;
	for (int j = 1; j < fragCount; ++j)
	{
		//binary search for insert position
		left = 0, right = j;
		while (left < right)
		{
			m = (left + right) >> 1;
			if (LFB_FRAG_DEPTH(CFRAG(j)) > LFB_FRAG_DEPTH(CFRAG(m)))
				left = m + 1;
			else
				right = m;
		}
		
		//if not already in order,
		if (j != left)
		{
			//if belongs in the second half of the circular buffer
			if (left > j / 2)
			{
				//swap into position normally (from tail)
				tmp = CFRAG(j);
				for (int i = j; i > left; --i)
					CFRAG(i) = CFRAG(i-1);
				CFRAG(left) = tmp;
			}
			else //else, should be less swaps starting from the other end
			{
				//swap into position the other way! dammit it I'm tired. firure it out for yourself
				tmp = CFRAG(j);
				
				//peel the tail into the hole created when shifting the circular buffer backwards
				CFRAG(j) = CFRAG(fragCount-1); //FIXME: one unnecessary right at the end
				
				//shift pointer backwards
				--c;
				
				//swap into position from head
				for (int i = 0; i < left; ++i)
					CFRAG(i) = CFRAG(i+1);
				CFRAG(left) = tmp;
			}
		}
	}
	
	//straighten the circular list
	//TODO: do this in less operations than fragCount
	int offset = 0;
	for (int i = 0; i < MAX_FRAGS; ++i)
	{
		tmp = FRAGS(offset);
		int a = offset;
		int b = (offset + c) % MAX_FRAGS;
		while (b != offset)
		{
			FRAGS(a) = FRAGS(b);
			a = b;
			b = (b + c) % MAX_FRAGS;
			++i;
		}
		FRAGS(a) = tmp;
		++offset;
	}
}

void sort_bitonic(int fragCount)
{
	int i,j,k;
	for (i = fragCount; i < MAX_FRAGS; ++i)
		LFB_FRAG_DEPTH(FRAGS(i)) = 99999.0;
		
	#define SWAP_BITONIC_SORT(a, b) \
		if (LFB_FRAG_DEPTH(FRAGS(a)) > LFB_FRAG_DEPTH(FRAGS(b))) \
		{ \
			tmp = FRAGS(a); FRAGS(a) = FRAGS(b); FRAGS(b) = tmp; \
		}

	LFB_FRAG_TYPE tmp;
	for (k=2;k<=MAX_FRAGS;k=k<<1) {
	  for (j=k>>1;j>0;j=j>>1) {
		for (i=0;i<MAX_FRAGS;i++) {
		  int ixj=i^j;
		  if (ixj > i)
		  {
		    if ((i&k)==0) SWAP_BITONIC_SORT(i,ixj)
		    if ((i&k)!=0) SWAP_BITONIC_SORT(ixj,i)
		  }
		}
	  }
	}
}
